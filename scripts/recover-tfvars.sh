#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# recover-tfvars.sh  —  rebuild a lost env/<ENV>.tfvars + backend files from state
#
# Usage:  ./scripts/recover-tfvars.sh <ENV> <REGION>
#   ENV     — environment name whose env/<ENV>.tfvars was lost
#   REGION  — AWS region it was deployed into (you already know this -- the
#             state bucket's own name embeds it, so there's no way to look
#             it up without it, unlike GCP's version of this script where
#             the project ID alone finds the bucket)
#
# What it does:
#   1. Reads the env's combined.tfstate directly from its S3 state bucket
#      (ekai-terraform-state-<ENV>-<REGION>) -- if that bucket is gone too,
#      there's nothing left to recover from and this can't help.
#   2. Pulls the one value that can't just come from env/customer.tfvars's
#      own defaults: dns_zone -- region and env are already known from the
#      arguments above, and everything else in the template (node size,
#      redis/neo4j toggles, cicd_provider, ...) is already a sensible
#      default. AWS has no equivalent of GCP's acme_email/tls_secret_name --
#      this repo uses ACM (DNS-validated, no email) and auto-generated
#      ssl_certificate_arn, not cert-manager/ACME.
#   3. Writes env/<ENV>.tfvars (starting from customer.tfvars, the values
#      above substituted in) and both backend config files.
#
# You still need to verify the result before trusting it with a destroy --
# run a terraform plan first (see the printed instructions at the end):
# expect no replacements, no large add/destroy counts.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ENV="${1:?Usage: $0 <ENV> <REGION>}"
REGION="${2:?Usage: $0 <ENV> <REGION>}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUCKET="ekai-terraform-state-${ENV}-${REGION}"
STATE_FILE="/tmp/${ENV}-combined.tfstate"

echo "==> Fetching s3://${BUCKET}/${ENV}/combined.tfstate ..."
aws s3 cp "s3://${BUCKET}/${ENV}/combined.tfstate" "${STATE_FILE}" --region "${REGION}"

echo "==> Extracting values from state..."
DNS_ZONE=$(python3 << PYEOF
import json

with open("${STATE_FILE}") as f:
    state = json.load(f)

def find(mod, typ, name):
    for r in state["resources"]:
        if r.get("module", "") == mod and r["type"] == typ and r["name"] == name and r.get("instances"):
            return r["instances"][0]["attributes"]
    return None

dnszone = find("module.infra.module.bootstrap", "aws_route53_zone", "main")
print(dnszone["name"].rstrip(".") if dnszone else "")
PYEOF
)

if [[ -z "${DNS_ZONE}" ]]; then
  echo "ERROR: couldn't find a managed Route53 zone in state -- either this env"
  echo "used manage_dns_zone = false (an existing zone, not Terraform-created),"
  echo "or the state file is from an older layout. Recover dns_zone manually"
  echo "and fill it into a copy of env/customer.tfvars instead."
  exit 1
fi

echo "  region:   ${REGION}"
echo "  dns_zone: ${DNS_ZONE}"

TFVARS_OUT="${REPO_ROOT}/env/${ENV}.tfvars"
if [[ -f "${TFVARS_OUT}" ]]; then
  echo "ERROR: ${TFVARS_OUT} already exists -- not overwriting. Delete it first if you want to regenerate."
  exit 1
fi

echo "==> Writing ${TFVARS_OUT}..."
sed \
  -e "s|^region[[:space:]]*=.*|region = \"${REGION}\"|" \
  -e "s|^env[[:space:]]*=.*|env = \"${ENV}\"|" \
  -e "s|^dns_zone[[:space:]]*=.*|dns_zone = \"${DNS_ZONE}\"|" \
  "${REPO_ROOT}/env/customer.tfvars" > "${TFVARS_OUT}"
echo "# Reconstructed from live Terraform state by recover-tfvars.sh -- verify" \
  "with a terraform plan before trusting it with a destroy." \
  | cat - "${TFVARS_OUT}" > "${TFVARS_OUT}.tmp" && mv "${TFVARS_OUT}.tmp" "${TFVARS_OUT}"

echo "==> Writing backend config files..."
cat > "${REPO_ROOT}/env/backend-${ENV}.tfbackend" << EOF
bucket  = "${BUCKET}"
key     = "${ENV}/combined.tfstate"
region  = "${REGION}"
encrypt = true
EOF
cat > "${REPO_ROOT}/env/backend-${ENV}-cicd.tfbackend" << EOF
bucket  = "${BUCKET}"
key     = "${ENV}/cicd.tfstate"
region  = "${REGION}"
encrypt = true
EOF

rm -f "${STATE_FILE}"

echo
echo "✓ Recovered env/${ENV}.tfvars + backend files."
echo "  Now verify before trusting it with a destroy:"
echo "    cd examples/self-deploy/root"
echo "    terraform init -reconfigure -backend-config=../../../env/backend-${ENV}.tfbackend"
echo "    terraform plan -var-file=../../../env/${ENV}.tfvars"
echo "  Expect no '# forces replacement' and no large add/destroy counts."
