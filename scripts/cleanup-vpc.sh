#!/bin/bash
# ============================================================================
# VPC Orphan Cleanup Script
# ============================================================================
# Deletes AWS resources created by Kubernetes controllers (ALB Controller,
# EKS CNI, EKS VPC endpoints) that Terraform does NOT manage and that block
# VPC deletion.
#
# Run after platform-layer destroy and before VPC destroy when:
#   DependencyViolation: The subnet '...' has dependencies
#   DependencyViolation: Network ... has some mapped public address(es)
#
# Usage:
#   ./scripts/cleanup-vpc.sh <vpc-id> <region>
# ============================================================================

set -euo pipefail

VPC_ID="${1:?Usage: $0 <vpc-id> <region>}"
REGION="${2:?Usage: $0 <vpc-id> <region>}"

echo "==========================================="
echo "  K8s Orphan Cleanup: $VPC_ID ($REGION)"
echo "==========================================="

# ── Step 1: Delete ALBs/NLBs created by ALB Controller ───────────────────────
echo ""
echo "[1/4] Deleting Load Balancers in VPC..."
LBS=$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" \
  --output text --region "$REGION" 2>/dev/null || true)

if [ -n "$LBS" ]; then
  for ARN in $LBS; do
    echo "  Deleting: $ARN"
    aws elbv2 delete-load-balancer --load-balancer-arn "$ARN" --region "$REGION" 2>/dev/null || true
  done
  echo "  Waiting 90s for ALB deletion and ENI release..."
  sleep 90
else
  echo "  No load balancers found."
fi

# ── Step 2: Delete VPC Interface Endpoints ────────────────────────────────────
# EKS creates VPC Interface Endpoints for cluster networking. These are not
# managed by Terraform and must be deleted before VPC subnets can be removed.
echo ""
echo "[2/4] Deleting VPC Interface Endpoints..."

# Include all active states — endpoint may be in 'deleting' from a previous
# failed destroy attempt; those are already being removed but ENIs still attached.
ENDPOINTS=$(aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'VpcEndpoints[?State!=`deleted`].VpcEndpointId' \
  --output text --region "$REGION" 2>/dev/null || true)

if [ -n "$ENDPOINTS" ]; then
  echo "  Found endpoints: $ENDPOINTS"
  # Delete only available/pending ones (deleting ones are already in progress)
  DELETABLE=$(aws ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'VpcEndpoints[?State==`available` || State==`pending`].VpcEndpointId' \
    --output text --region "$REGION" 2>/dev/null || true)
  for EP in $DELETABLE; do
    echo "  Deleting: $EP"
    aws ec2 delete-vpc-endpoints --vpc-endpoint-ids "$EP" --region "$REGION" 2>/dev/null || true
  done
  echo "  Waiting 90s for endpoint ENIs to release..."
  sleep 90
  # Verify endpoints are gone
  REMAINING=$(aws ec2 describe-network-interfaces \
    --filters "Name=vpc-id,Values=$VPC_ID" \
              "Name=interface-type,Values=vpc_endpoint" \
    --query 'NetworkInterfaces[*].NetworkInterfaceId' \
    --output text --region "$REGION" 2>/dev/null || true)
  if [ -n "$REMAINING" ]; then
    echo "  Endpoint ENIs still present, waiting 60s more..."
    sleep 60
  fi
else
  echo "  No VPC Interface Endpoints found."
fi

# ── Step 3: Delete K8s-created Security Groups ───────────────────────────────
# ALB controller creates a frontend SG and a backend node-port SG that each
# have ingress/egress rules referencing the other. Attempting to delete either
# while the cross-reference exists fails with DependencyViolation. Revoke all
# SG-to-SG rules first, then delete the SGs.
echo ""
echo "[3/4] Deleting K8s-created Security Groups (tagged kubernetes.io/cluster/*)..."
K8S_SGS=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$VPC_ID" \
             "Name=tag-key,Values=kubernetes.io/cluster/*" \
  --query 'SecurityGroups[*].GroupId' \
  --output text --region "$REGION" 2>/dev/null || true)

ALB_SGS=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$VPC_ID" \
             "Name=tag-key,Values=elbv2.k8s.aws/cluster" \
  --query 'SecurityGroups[*].GroupId' \
  --output text --region "$REGION" 2>/dev/null || true)

ALL_K8S_SGS="$K8S_SGS $ALB_SGS"

# First pass: revoke all SG-to-SG ingress and egress rules (breaks cross-refs)
for SG in $ALL_K8S_SGS; do
  [ -z "$SG" ] && continue
  INGRESS=$(aws ec2 describe-security-groups --group-ids "$SG" --region "$REGION" \
    --query 'SecurityGroups[0].IpPermissions[?UserIdGroupPairs!=`[]`]' \
    --output json 2>/dev/null || echo "[]")
  if [ "$INGRESS" != "[]" ] && [ "$INGRESS" != "null" ] && [ -n "$INGRESS" ]; then
    aws ec2 revoke-security-group-ingress \
      --group-id "$SG" --ip-permissions "$INGRESS" \
      --region "$REGION" 2>/dev/null || true
  fi
  EGRESS=$(aws ec2 describe-security-groups --group-ids "$SG" --region "$REGION" \
    --query 'SecurityGroups[0].IpPermissionsEgress[?UserIdGroupPairs!=`[]`]' \
    --output json 2>/dev/null || echo "[]")
  if [ "$EGRESS" != "[]" ] && [ "$EGRESS" != "null" ] && [ -n "$EGRESS" ]; then
    aws ec2 revoke-security-group-egress \
      --group-id "$SG" --ip-permissions "$EGRESS" \
      --region "$REGION" 2>/dev/null || true
  fi
done

# Second pass: delete the now-isolated SGs
for SG in $ALL_K8S_SGS; do
  [ -z "$SG" ] && continue
  echo "  Deleting: $SG"
  aws ec2 delete-security-group --group-id "$SG" --region "$REGION" 2>/dev/null || true
done

if [ -z "$(echo "$ALL_K8S_SGS" | tr -d ' ')" ]; then
  echo "  No K8s-created security groups found."
fi

# ── Step 4: Delete any remaining non-default security groups ─────────────────
# AWS-managed SGs (e.g. GuardDutyManagedSecurityGroup) block VPC deletion.
# Delete all non-default SGs not already handled above.
echo ""
echo "[4/5] Deleting remaining non-default security groups..."
REMAINING_SGS=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
  --output text --region "$REGION" 2>/dev/null || true)

for SG in $REMAINING_SGS; do
  [ -z "$SG" ] && continue
  # Revoke cross-references first
  INGRESS=$(aws ec2 describe-security-groups --group-ids "$SG" --region "$REGION" \
    --query 'SecurityGroups[0].IpPermissions[?UserIdGroupPairs!=`[]`]' \
    --output json 2>/dev/null || echo "[]")
  if [ "$INGRESS" != "[]" ] && [ "$INGRESS" != "null" ] && [ -n "$INGRESS" ]; then
    aws ec2 revoke-security-group-ingress \
      --group-id "$SG" --ip-permissions "$INGRESS" \
      --region "$REGION" 2>/dev/null || true
  fi
  echo "  Deleting: $SG"
  aws ec2 delete-security-group --group-id "$SG" --region "$REGION" 2>/dev/null || true
done

if [ -z "$(echo "$REMAINING_SGS" | tr -d ' \t')" ]; then
  echo "  No remaining security groups found."
fi

# ── Step 5: Delete orphan ENIs (available, not attached to anything) ──────────
echo ""
echo "[5/5] Deleting orphan ENIs in 'available' state..."
ENIS=$(aws ec2 describe-network-interfaces \
  --filters "Name=vpc-id,Values=$VPC_ID" \
            "Name=status,Values=available" \
  --query 'NetworkInterfaces[*].NetworkInterfaceId' \
  --output text --region "$REGION" 2>/dev/null || true)

if [ -n "$ENIS" ]; then
  for ENI in $ENIS; do
    echo "  Deleting: $ENI"
    aws ec2 delete-network-interface --network-interface-id "$ENI" --region "$REGION" 2>/dev/null || true
  done
else
  echo "  No orphan ENIs found."
fi

echo ""
echo "==========================================="
echo "  Cleanup complete."
echo "==========================================="
