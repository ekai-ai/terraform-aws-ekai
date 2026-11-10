#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# init-state-backend.sh  —  AWS Terraform state bootstrap
#
# Usage:  ./scripts/init-state-backend.sh <ENV>
#
# What it does:
#   1. Reads region from env/<ENV>.tfvars
#   2. Creates (or verifies) an S3 bucket:
#      ekai-terraform-state-<ENV>-<REGION>-<ACCOUNT_ID>
#      with versioning + AES256 encryption + public-access block. The
#      account ID suffix matters because S3 bucket names are globally
#      unique across every AWS account, not just within this one -- without
#      it, two different customers picking the same env/region collide.
#   3. Writes TWO backend config files, one per state-holding root config
#      (down from the original 4 layers, but not all the way to 1 — see
#      cicd/main.tf's file header for why the cicd apply has to stay
#      separate). The repo root and cicd/ are Terraform modules (no backend
#      block of their own); examples/self-deploy/{root,cicd} are the actual
#      root configs that use these files:
#        env/backend-<ENV>.tfbackend       — examples/self-deploy/root (bootstrap+cluster+platform)
#        env/backend-<ENV>-cicd.tfbackend  — examples/self-deploy/cicd
#
# Idempotent — safe to run multiple times; existing resources are not modified.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Args ──────────────────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <ENV>"
  echo "  ENV  one of: dev, test, qa, staging, prod"
  exit 1
fi
ENV="$1"

TFVARS="${REPO_ROOT}/env/${ENV}.tfvars"
if [[ ! -f "${TFVARS}" ]]; then
  echo "ERROR: ${TFVARS} not found."
  exit 1
fi

# ── Extract region from tfvars ────────────────────────────────────────────────
REGION=$(grep -E '^region[[:space:]]*=' "${TFVARS}" | head -1 | sed 's/.*=[[:space:]]*"\(.*\)".*/\1/')
if [[ -z "${REGION}" ]]; then
  echo "ERROR: could not extract 'region' from ${TFVARS}"
  exit 1
fi

# Env value from tfvars — may differ from the ENV argument (the tfvars
# filename), e.g. env/umar.tfvars containing env = "umar-test". Used below
# for both the bucket name and the state key, so it always matches what
# cicd/main.tf's own data "terraform_remote_state" "combined" block computes
# ("ekai-terraform-state-${var.env}-${var.region}-${data.aws_caller_identity.current.account_id}")
# -- that data source has no access to this script's ENV argument, only to
# var.env (and resolves the account ID itself via aws_caller_identity, the
# same way this script resolves it via `aws sts get-caller-identity` below).
ENV_PREFIX=$(grep -E '^env[[:space:]]*=' "${TFVARS}" | head -1 | sed 's/.*=[[:space:]]*"\(.*\)".*/\1/')
if [[ -z "${ENV_PREFIX}" ]]; then
  ENV_PREFIX="${ENV}"
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="ekai-terraform-state-${ENV_PREFIX}-${REGION}-${ACCOUNT_ID}"
echo "==> State bucket: ${BUCKET} (region: ${REGION})"

# ── Create or verify S3 bucket ────────────────────────────────────────────────
if aws s3api head-bucket --bucket "${BUCKET}" --region "${REGION}" 2>/dev/null; then
  echo "==> Bucket already exists — skipping creation."
else
  echo "==> Creating bucket..."
  # A same-day destroy-then-redeploy of the same env hits this bucket name
  # again within minutes of its deletion -- S3 can still be finishing that
  # delete internally and rejects the recreate with a transient
  # "OperationAborted: A conflicting conditional operation is currently in
  # progress against this resource" for up to a couple of minutes. Retry
  # specifically on that error; anything else (e.g. a real name collision
  # with another AWS account) fails immediately instead of retrying 5 times
  # for nothing.
  for attempt in $(seq 1 5); do
    CREATE_ERR=$(
      if [[ "${REGION}" == "us-east-1" ]]; then
        aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}" 2>&1
      else
        aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}" \
          --create-bucket-configuration LocationConstraint="${REGION}" 2>&1
      fi
    ) && { CREATE_ERR=""; break; }
    if ! echo "${CREATE_ERR}" | grep -q "OperationAborted"; then
      echo "${CREATE_ERR}" >&2
      exit 1
    fi
    echo "==> Bucket recently deleted and still settling (OperationAborted) -- retrying in 15s (attempt ${attempt}/5)..."
    sleep 15
  done
  if [[ -n "${CREATE_ERR}" ]]; then
    echo "${CREATE_ERR}" >&2
    echo "ERROR: bucket still not creatable after 5 attempts -- try again in a minute." >&2
    exit 1
  fi
fi

# ── Versioning ────────────────────────────────────────────────────────────────
echo "==> Enabling versioning..."
aws s3api put-bucket-versioning \
  --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled \
  --region "${REGION}"

# ── Encryption ────────────────────────────────────────────────────────────────
echo "==> Enabling AES256 encryption..."
aws s3api put-bucket-encryption \
  --bucket "${BUCKET}" \
  --region "${REGION}" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      },
      "BucketKeyEnabled": true
    }]
  }'

# ── Block public access ───────────────────────────────────────────────────────
echo "==> Blocking public access..."
aws s3api put-public-access-block \
  --bucket "${BUCKET}" \
  --region "${REGION}" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# ── Write backend config files ────────────────────────────────────────────────
ENV_DIR="${REPO_ROOT}/env"

ROOT_BACKEND_FILE="${ENV_DIR}/backend-${ENV}.tfbackend"
echo "==> Writing ${ROOT_BACKEND_FILE}..."
cat > "${ROOT_BACKEND_FILE}" <<EOF
bucket  = "${BUCKET}"
key     = "${ENV_PREFIX}/combined.tfstate"
region  = "${REGION}"
encrypt = true
EOF

CICD_BACKEND_FILE="${ENV_DIR}/backend-${ENV}-cicd.tfbackend"
echo "==> Writing ${CICD_BACKEND_FILE}..."
cat > "${CICD_BACKEND_FILE}" <<EOF
bucket  = "${BUCKET}"
key     = "${ENV_PREFIX}/cicd.tfstate"
region  = "${REGION}"
encrypt = true
EOF

echo ""
echo "✓ Done. Backend files written to ${ROOT_BACKEND_FILE} and ${CICD_BACKEND_FILE}"
echo ""
echo "Apply, in order (the repo root and cicd/ are Terraform modules, not"
echo "applyable directly — examples/self-deploy/{root,cicd} are the actual"
echo "state-holding root configs that wrap them):"
echo "  cd examples/self-deploy/root"
echo "  terraform init -backend-config=../../../env/backend-${ENV}.tfbackend"
echo "  terraform apply -var-file=../../../env/${ENV}.tfvars"
echo "  cd ../cicd"
echo "  terraform init -backend-config=../../../env/backend-${ENV}-cicd.tfbackend"
echo "  terraform apply -var-file=../../../env/${ENV}.tfvars"
