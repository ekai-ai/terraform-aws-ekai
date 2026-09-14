#!/bin/bash
# ============================================================================
# AWS Environment Cleanup Script
# ============================================================================
# Run AFTER terraform destroy to fully reset an environment.
# Removes resources that Terraform cannot or does not delete on destroy:
#   1. S3 state bucket (versioned — must be emptied before deletion)
#   2. ECR repositories (force-deletes including all images)
#   3. CloudWatch log groups (EKS control plane + app logs)
#   4. Secrets Manager secrets (force-delete, no recovery period)
#
# Usage:
#   ./scripts/cleanup-aws-env.sh <env> <region> [--yes]
#
# Example:
#   ./scripts/cleanup-aws-env.sh client1 us-east-1 --yes
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ENV="${1:?Usage: $0 <env> <region> [--yes]}"
REGION="${2:?Usage: $0 <env> <region> [--yes]}"
AUTO_YES="${3:-}"

# Env value from tfvars — may differ from ENV (the tfvars filename), e.g.
# env/umar.tfvars containing env = "umar-test". The state bucket was
# actually created/named using this value, not necessarily this script's
# ENV argument — see init-state-backend.sh. Falls back to ENV as-is when
# no matching tfvars file exists (this script is also runnable standalone).
ENV_PREFIX="${ENV}"
TFVARS="${REPO_ROOT}/env/${ENV}.tfvars"
if [[ -f "${TFVARS}" ]]; then
  FOUND=$(grep -E '^env\s*=' "${TFVARS}" | head -1 | sed 's/.*=\s*"\(.*\)".*/\1/' || true)
  [[ -n "${FOUND}" ]] && ENV_PREFIX="${FOUND}"
fi

BUCKET="ekai-terraform-state-${ENV_PREFIX}-${REGION}"

if [ "$AUTO_YES" != "--yes" ]; then
  echo "WARNING: This will permanently delete:"
  echo "  - S3 state bucket   : $BUCKET"
  echo "  - ECR repositories  : ${ENV_PREFIX}-*"
  echo "  - CW log groups     : /aws/eks/${ENV_PREFIX}* and /ekai/${ENV_PREFIX}*"
  echo "  - Secrets Manager   : ${ENV_PREFIX}-ekai-db-credentials only (client secrets preserved)"
  echo ""
  read -rp "Type 'yes' to continue: " confirm
  [ "$confirm" = "yes" ] || { echo "Aborted."; exit 0; }
fi

echo "==========================================="
echo "  AWS Cleanup: $ENV ($REGION)"
echo "==========================================="

# 1. Empty + delete S3 state bucket (versioned)
echo ""
echo "[1/4] Deleting S3 state bucket: $BUCKET"
if aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null; then
  # Delete all versioned objects
  VERSIONS=$(aws s3api list-object-versions --bucket "$BUCKET" --region "$REGION" \
    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
    --output json 2>/dev/null)
  if [ "$(echo "$VERSIONS" | jq '.Objects | length')" -gt 0 ]; then
    aws s3api delete-objects --bucket "$BUCKET" --region "$REGION" \
      --delete "$VERSIONS" > /dev/null
  fi
  # Delete all delete markers
  MARKERS=$(aws s3api list-object-versions --bucket "$BUCKET" --region "$REGION" \
    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
    --output json 2>/dev/null)
  if [ "$(echo "$MARKERS" | jq '.Objects | length')" -gt 0 ]; then
    aws s3api delete-objects --bucket "$BUCKET" --region "$REGION" \
      --delete "$MARKERS" > /dev/null
  fi
  aws s3 rb "s3://$BUCKET" --region "$REGION"
  echo "  Deleted: $BUCKET"
else
  echo "  Not found: $BUCKET — skipping"
fi

# 2. Force-delete ECR repositories (removes all images)
echo ""
echo "[2/4] Deleting ECR repositories: ${ENV_PREFIX}-*"
REPOS=$(aws ecr describe-repositories --region "$REGION" \
  --query "repositories[?starts_with(repositoryName, '${ENV_PREFIX}-')].repositoryName" \
  --output text 2>/dev/null || true)
if [ -z "$REPOS" ]; then
  echo "  No repositories found"
else
  for repo in $REPOS; do
    aws ecr delete-repository --repository-name "$repo" --force --region "$REGION" > /dev/null
    echo "  Deleted: $repo"
  done
fi

# 3. Delete CloudWatch log groups
echo ""
echo "[3/4] Deleting CloudWatch log groups"
for PREFIX in "/aws/eks/${ENV_PREFIX}" "/ekai/${ENV_PREFIX}" "/aws/codebuild/${ENV_PREFIX}"; do
  LGS=$(aws logs describe-log-groups --region "$REGION" \
    --log-group-name-prefix "$PREFIX" \
    --query 'logGroups[*].logGroupName' --output text 2>/dev/null || true)
  for lg in $LGS; do
    aws logs delete-log-group --log-group-name "$lg" --region "$REGION"
    echo "  Deleted: $lg"
  done
done

# 4. Force-delete master DB credentials secret only.
# Client-managed per-service secrets (${ENV_PREFIX}-ekai-backend, ${ENV_PREFIX}-ekai-erd, etc.)
# are intentionally preserved — client owns them.
echo ""
echo "[4/4] Deleting master secret: ${ENV_PREFIX}-ekai-db-credentials"
MASTER_SECRET="${ENV_PREFIX}-ekai-db-credentials"
if aws secretsmanager describe-secret --secret-id "$MASTER_SECRET" \
    --region "$REGION" > /dev/null 2>&1; then
  aws secretsmanager delete-secret --secret-id "$MASTER_SECRET" \
    --force-delete-without-recovery --region "$REGION" > /dev/null
  echo "  Deleted: $MASTER_SECRET"
else
  echo "  Not found: $MASTER_SECRET — skipping"
fi

echo ""
echo "==========================================="
echo "  Cleanup complete."
echo "==========================================="
