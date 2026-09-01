#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# self-deploy-destroy.sh  —  tear down what self-deploy.sh created
#
# Usage:  ./scripts/self-deploy-destroy.sh <ENV>
#
# The repo root and cicd/ are reusable Terraform modules (no backend block
# of their own — see providers.tf / cicd/providers.tf); the actual
# state-holding root configs that apply/destroy them live at
# examples/self-deploy/{root,cicd} (down from the original 4 layers, but not
# all the way to 1 — see cicd/main.tf's file header for why the cicd apply
# has to stay separate from root's). Destroy runs in reverse dependency order:
#   1. terraform destroy in cicd/ FIRST — it depends on the root config's
#      cluster/ArgoCD still being live (its kubernetes/kubectl/argocd
#      providers need a real API server + running ArgoCD to clean up
#      ExternalSecrets/ServiceAccounts/the ArgoCD Application against), same
#      as the original script destroyed 04-cicd before 03-platform/02-cluster.
#   2. terraform destroy in the repo root (bootstrap+cluster+platform,
#      combined) — Terraform sequences this internally in reverse dependency
#      order (platform, then cluster, then bootstrap — see main.tf's module
#      depends_on chain), with a VPC-orphan-cleanup retry if the first
#      attempt fails on a VPC DependencyViolation (ALBs/ENIs the ALB
#      controller hasn't finished releasing yet) — the same retry structure
#      the old 4-separate-states script applied to its final 01-bootstrap
#      destroy.
#   3. optional: delete the S3 state bucket, ECR repos, CloudWatch logs, and
#      the master Secrets Manager secret (cleanup-aws-env.sh)
#   4. optional: delete the per-service secrets self-deploy.sh created
#   5. optional: delete the ekai-terraform-<env> IAM user + its access key
#      (the shared ekai-terraform-policy-infra/-cicd policies are left alone —
#      other environments' users are attached to them too)
#
# Each destructive stage has its own confirmation — say no to any of them and
# the rest still runs. Safe to re-run if it fails partway.
#
# Requires: aws cli, terraform, jq.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <ENV>"
  exit 1
fi
ENV="$1"
TFVARS="${REPO_ROOT}/env/${ENV}.tfvars"

if [[ ! -f "${TFVARS}" ]]; then
  echo "ERROR: ${TFVARS} not found."
  exit 1
fi

for bin in aws terraform jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: '$bin' is required but not installed."; exit 1; }
done

REGION=$(grep -E '^region\s*=' "${TFVARS}" | head -1 | sed 's/.*=\s*"\(.*\)".*/\1/')
[[ -z "${REGION}" ]] && { echo "ERROR: could not read 'region' from ${TFVARS}"; exit 1; }

echo "════════════════════════════════════════════════════════════════"
echo " Ekai AWS self-deploy DESTROY — environment: ${ENV} (region: ${REGION})"
echo "════════════════════════════════════════════════════════════════"
echo
echo "This will permanently destroy the VPC, EKS cluster, RDS database,"
echo "ArgoCD, CI/CD pipelines, and DNS zone for '${ENV}'. This cannot be undone."
echo
read -rp "Type the environment name (${ENV}) to confirm: " CONFIRM_ENV
if [[ "${CONFIRM_ENV}" != "${ENV}" ]]; then
  echo "Did not match — aborted. Nothing was touched."
  exit 1
fi

# Same reason as self-deploy.sh's Step 1: the Kubernetes/Helm resources in
# every layer only grant access to the ekai-terraform-<env> identity
# (cluster-creator exemption + aws-auth mapUsers), never to whatever AWS
# credentials happen to be ambient in this shell. Without this, every
# kubernetes_namespace/helm_release destroy fails with "Unauthorized" even
# though the AWS-level destroy calls (RDS, VPC, ...) would have worked fine.
USER_NAME="ekai-terraform-${ENV}"
echo
echo "==> Minting a fresh access key for ${USER_NAME} (destroy needs the same"
echo "    identity that created the cluster — ambient credentials won't have"
echo "    Kubernetes RBAC access)..."
mapfile -t EXISTING_KEYS < <(aws iam list-access-keys --user-name "${USER_NAME}" --query 'sort_by(AccessKeyMetadata, &CreateDate)[].AccessKeyId' --output text 2>/dev/null | tr '\t' '\n')
if [[ ${#EXISTING_KEYS[@]} -ge 2 ]]; then
  echo "    ${USER_NAME} already has 2 access keys (AWS's max) — deleting the oldest (${EXISTING_KEYS[0]}) to make room."
  aws iam delete-access-key --user-name "${USER_NAME}" --access-key-id "${EXISTING_KEYS[0]}"
  EXISTING_KEYS=("${EXISTING_KEYS[@]:1}")
fi
# Key management itself (create/deactivate) runs on the operator's own
# ambient credentials the whole time -- a just-created key needs a few
# seconds to propagate before AWS will accept it for ANY call, including
# deactivating the old ones. Only switch AWS_ACCESS_KEY_ID/SECRET over
# after that propagation wait, right before it's actually needed.
AK_JSON=$(aws iam create-access-key --user-name "${USER_NAME}")
TF_AWS_ACCESS_KEY_ID=$(echo "${AK_JSON}" | jq -r .AccessKey.AccessKeyId)
TF_AWS_SECRET_ACCESS_KEY=$(echo "${AK_JSON}" | jq -r .AccessKey.SecretAccessKey)
for OLD_KEY in "${EXISTING_KEYS[@]}"; do
  aws iam update-access-key --user-name "${USER_NAME}" --access-key-id "${OLD_KEY}" --status Inactive
done
echo "    Waiting for the new key to propagate..."
for i in $(seq 1 10); do
  AWS_ACCESS_KEY_ID="${TF_AWS_ACCESS_KEY_ID}" AWS_SECRET_ACCESS_KEY="${TF_AWS_SECRET_ACCESS_KEY}" \
    aws sts get-caller-identity >/dev/null 2>&1 && { echo "    ✓ Key is active."; break; }
  sleep 3
done

# Save whatever credential env vars the operator's own shell already had (if
# any) so Section 5 below can restore them -- ekai-terraform-policy-infra/-cicd
# grant no iam:*User*/iam:*AccessKey* actions at all (not even for
# self-management), so deleting ekai-terraform-<env> itself needs the
# operator's own admin identity back, not the scoped one exported next.
_ORIG_AWS_ACCESS_KEY_ID_SET="${AWS_ACCESS_KEY_ID+x}"
_ORIG_AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID-}"
_ORIG_AWS_SECRET_ACCESS_KEY_SET="${AWS_SECRET_ACCESS_KEY+x}"
_ORIG_AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY-}"
_ORIG_AWS_SESSION_TOKEN_SET="${AWS_SESSION_TOKEN+x}"
_ORIG_AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN-}"
restore_admin_credentials() {
  if [[ -n "${_ORIG_AWS_ACCESS_KEY_ID_SET}" ]]; then export AWS_ACCESS_KEY_ID="${_ORIG_AWS_ACCESS_KEY_ID}"; else unset AWS_ACCESS_KEY_ID; fi
  if [[ -n "${_ORIG_AWS_SECRET_ACCESS_KEY_SET}" ]]; then export AWS_SECRET_ACCESS_KEY="${_ORIG_AWS_SECRET_ACCESS_KEY}"; else unset AWS_SECRET_ACCESS_KEY; fi
  if [[ -n "${_ORIG_AWS_SESSION_TOKEN_SET}" ]]; then export AWS_SESSION_TOKEN="${_ORIG_AWS_SESSION_TOKEN}"; else unset AWS_SESSION_TOKEN; fi
}

export AWS_ACCESS_KEY_ID="${TF_AWS_ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${TF_AWS_SECRET_ACCESS_KEY}"

# Both destroys run from examples/self-deploy/{cicd,root} — the repo root
# and cicd/ directories are pure Terraform modules now (no backend block of
# their own), so they can't be applied/destroyed directly. See
# examples/self-deploy/root/main.tf's header comment.
vpc_cleanup() {
  echo "==> Checking for VPC orphan resources (ALBs, ENIs, SGs)..."
  cd "${REPO_ROOT}/examples/self-deploy/root"
  VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")
  if [[ -z "${VPC_ID}" || "${VPC_ID}" == "null" ]]; then
    echo "    No VPC ID found — skipping."
    return
  fi
  "${SCRIPT_DIR}/cleanup-vpc.sh" "${VPC_ID}" "${REGION}"
}

# ── 1. Terraform destroy — cicd/ first ────────────────────────────────────────
# Must run while the root config's cluster/ArgoCD are still live — cicd's
# kubernetes/kubectl/argocd providers (configured from a remote_state read
# against the root's state — see cicd/providers.tf) need a real API server
# and a running ArgoCD to clean up ExternalSecrets/ServiceAccounts/the ArgoCD
# Application against.
echo
echo "════════ terraform destroy (cicd) ════════"
cd "${REPO_ROOT}/examples/self-deploy/cicd"
terraform init -upgrade -reconfigure -backend-config="../../../env/backend-${ENV}-cicd.tfbackend" 1>/dev/null
terraform destroy -auto-approve -compact-warnings -var-file="../../../env/${ENV}.tfvars"

echo
echo "✓ cicd destroyed for env=${ENV}."

# ── 2. Terraform destroy — repo root (bootstrap+cluster+platform) ────────────
# Terraform sequences this internally in reverse dependency order — platform,
# then cluster, then bootstrap (see main.tf's module depends_on chain) — the
# same order the old 4-separate-states script used to drive by hand across
# 03-platform/02-cluster/01-bootstrap (now that cicd is already gone above).
#
# VPC teardown is still the fragile part (ALB controller / EKS control-plane
# ENIs can lag behind their own resource deletion), so the retry-with-cleanup
# structure that used to apply only to the final 01-bootstrap destroy now
# applies to this combined destroy instead.
echo
echo "════════ terraform destroy (bootstrap + cluster + platform) ════════"
cd "${REPO_ROOT}/examples/self-deploy/root"
terraform init -upgrade -reconfigure -backend-config="../../../env/backend-${ENV}.tfbackend" 1>/dev/null
if ! terraform destroy -auto-approve -compact-warnings -var-file="../../../env/${ENV}.tfvars"; then
  echo "First destroy attempt failed — re-running VPC cleanup and retrying once..."
  vpc_cleanup
  echo "==> Waiting 5 minutes for EKS control-plane ENIs / ALBs to fully release before retrying..."
  sleep 300
  terraform refresh -compact-warnings -var-file="../../../env/${ENV}.tfvars" 2>/dev/null || true
  terraform destroy -auto-approve -compact-warnings -var-file="../../../env/${ENV}.tfvars"
fi

echo
echo "✓ Terraform infrastructure destroyed for env=${ENV}."

# ── 3. Optional: S3 state bucket + ECR + CW logs + master secret ─────────────
echo
read -rp "Also delete the S3 state bucket, ECR repos, CloudWatch logs, and master secret? [y/N] " CLEAN_AWS
if [[ "${CLEAN_AWS}" =~ ^[Yy]$ ]]; then
  "${SCRIPT_DIR}/cleanup-aws-env.sh" "${ENV}" "${REGION}" --yes
else
  echo "Skipped — the env name (${ENV}) is not reusable until this is run, since the S3 state bucket still exists."
fi

# ── 4. Optional: per-service secrets self-deploy.sh created ──────────────────
echo
read -rp "Also delete the per-service secrets (${ENV}-ekai-backend/erd/semantics/profile)? [y/N] " CLEAN_SVC
if [[ "${CLEAN_SVC}" =~ ^[Yy]$ ]]; then
  for SVC in ekai-backend ekai-erd ekai-semantics ekai-profile; do
    SNAME="${ENV}-${SVC}"
    if aws secretsmanager describe-secret --secret-id "${SNAME}" --region "${REGION}" >/dev/null 2>&1; then
      aws secretsmanager delete-secret --secret-id "${SNAME}" --region "${REGION}" --force-delete-without-recovery >/dev/null
      echo "  Deleted: ${SNAME}"
    fi
  done
else
  echo "Skipped."
fi

# ── 5. Optional: the IAM user self-deploy.sh created ──────────────────────────
# Restore the operator's own admin credentials -- everything from here on
# (deleting an IAM user, its access keys, its policy attachments) needs
# admin-level IAM permissions the scoped ekai-terraform-<env> user was never
# granted, not even for managing itself.
restore_admin_credentials
echo
USER_NAME="ekai-terraform-${ENV}"
read -rp "Also delete the IAM user ${USER_NAME} and its access key? [y/N] " CLEAN_IAM
if [[ "${CLEAN_IAM}" =~ ^[Yy]$ ]]; then
  if aws iam get-user --user-name "${USER_NAME}" >/dev/null 2>&1; then
    for KEY in $(aws iam list-access-keys --user-name "${USER_NAME}" --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
      aws iam delete-access-key --user-name "${USER_NAME}" --access-key-id "${KEY}"
      echo "  Deleted access key: ${KEY}"
    done
    aws iam detach-user-policy --user-name "${USER_NAME}" --policy-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/ekai-terraform-policy-infra" 2>/dev/null || true
    aws iam detach-user-policy --user-name "${USER_NAME}" --policy-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/ekai-terraform-policy-cicd" 2>/dev/null || true
    aws iam delete-user --user-name "${USER_NAME}"
    echo "  Deleted IAM user: ${USER_NAME}"
    echo "  (ekai-terraform-policy-infra/-cicd left in place — other environments use them)"
  else
    echo "  ${USER_NAME} not found — skipping."
  fi
else
  echo "Skipped."
fi

echo
echo "✓ Done."
