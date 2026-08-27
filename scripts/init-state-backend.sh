#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# init-state-backend.sh  —  AWS Terraform state bootstrap
#
# Usage:  ./scripts/init-state-backend.sh <ENV>
#
# What it does:
#   1. Reads region from env/<ENV>.tfvars
#   2. Creates (or verifies) an S3 bucket: ekai-terraform-state-<ENV>-<REGION>
#      with versioning + AES256 encryption + public-access block
#   3. Writes TWO backend config files — this repo is 2 Terraform root
#      configs (down from the original 4 layers, but not all the way to 1 —
#      see cicd/main.tf's file header for why the cicd apply has to stay
#      separate):
#        env/backend-<ENV>.tfbackend       — repo root (bootstrap+cluster+platform)
#        env/backend-<ENV>-cicd.tfbackend  — cicd/
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
REGION=$(grep -E '^region\s*=' "${TFVARS}" | head -1 | sed 's/.*=\s*"\(.*\)".*/\1/')
if [[ -z "${REGION}" ]]; then
  echo "ERROR: could not extract 'region' from ${TFVARS}"
  exit 1
fi

BUCKET="ekai-terraform-state-${ENV}-${REGION}"
echo "==> State bucket: ${BUCKET} (region: ${REGION})"

# ── Create or verify S3 bucket ────────────────────────────────────────────────
if aws s3api head-bucket --bucket "${BUCKET}" --region "${REGION}" 2>/dev/null; then
  echo "==> Bucket already exists — skipping creation."
else
  echo "==> Creating bucket..."
  if [[ "${REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket \
      --bucket "${BUCKET}" \
      --region "${REGION}"
  else
    aws s3api create-bucket \
      --bucket "${BUCKET}" \
      --region "${REGION}" \
      --create-bucket-configuration LocationConstraint="${REGION}"
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
key     = "${ENV}/combined.tfstate"
region  = "${REGION}"
encrypt = true
EOF

CICD_BACKEND_FILE="${ENV_DIR}/backend-${ENV}-cicd.tfbackend"
echo "==> Writing ${CICD_BACKEND_FILE}..."
cat > "${CICD_BACKEND_FILE}" <<EOF
bucket  = "${BUCKET}"
key     = "${ENV}/cicd.tfstate"
region  = "${REGION}"
encrypt = true
EOF

echo ""
echo "✓ Done. Backend files written to ${ROOT_BACKEND_FILE} and ${CICD_BACKEND_FILE}"
echo ""
echo "Apply, in order:"
echo "  terraform init -backend-config=env/backend-${ENV}.tfbackend"
echo "  terraform apply -var-file=env/${ENV}.tfvars"
echo "  cd cicd"
echo "  terraform init -backend-config=../env/backend-${ENV}-cicd.tfbackend"
echo "  terraform apply -var-file=../env/${ENV}.tfvars"
