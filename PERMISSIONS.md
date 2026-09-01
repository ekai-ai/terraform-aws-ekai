# Permissions the bootstrapping identity actually needs

`scripts/self-deploy.sh` and `scripts/self-deploy-destroy.sh` run as **two
different AWS identities**, not one:

1. **The bootstrapping identity** — whatever's active in your terminal when
   you run the script (`aws configure`'d credentials, an SSO session, a named
   profile, ...). Its only job is creating/deleting one specific IAM user and
   its two specific IAM policies. It never touches EC2/EKS/RDS/S3 directly.
2. **The scoped deployer** (`ekai-terraform-<env>`) — a fresh IAM user the
   bootstrapping identity creates. Terraform runs as *this* identity for
   everything else (VPC, EKS, RDS, ALB, Secrets Manager, ...), via the
   `ekai-terraform-policy-infra`/`ekai-terraform-policy-cicd` policies the
   script generates for you (see `scripts/self-deploy.sh` for their exact
   content — no need to hand-author or review those).

This file is about identity 1 only. The README's "admin rights" phrasing was
broader than reality — traced against every AWS CLI call both scripts
actually make (not identity 2's, which are self-contained in the policies
above), the real requirement is exactly this, nothing more:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ManageTheScopedDeployerUser",
      "Effect": "Allow",
      "Action": [
        "iam:GetUser",
        "iam:CreateUser",
        "iam:DeleteUser",
        "iam:AttachUserPolicy",
        "iam:DetachUserPolicy",
        "iam:ListAccessKeys",
        "iam:CreateAccessKey",
        "iam:DeleteAccessKey",
        "iam:UpdateAccessKey"
      ],
      "Resource": "arn:aws:iam::*:user/ekai-terraform-*"
    },
    {
      "Sid": "ManageTheScopedDeployerPolicies",
      "Effect": "Allow",
      "Action": [
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:ListPolicyVersions",
        "iam:CreatePolicy",
        "iam:CreatePolicyVersion",
        "iam:DeletePolicyVersion"
      ],
      "Resource": "arn:aws:iam::*:policy/ekai-terraform-policy-*"
    },
    {
      "Sid": "WhoAmI",
      "Effect": "Allow",
      "Action": "sts:GetCallerIdentity",
      "Resource": "*"
    }
  ]
}
```

That's the entire bootstrapping identity's footprint: create/delete one IAM
user matching `ekai-terraform-*`, create/version two IAM policies matching
`ekai-terraform-policy-*`, and identify itself. It cannot read or modify
anything the scoped deployer later creates — no VPC, no EKS, no RDS, no
Secrets Manager, no S3 — those all belong to identity 2's own policy.

## Where each permission is used

| Permission | Where | Why |
|---|---|---|
| `sts:GetCallerIdentity` | both scripts, throughout | reads the account ID to build ARNs; confirms who's currently authenticated |
| `iam:GetPolicy` / `GetPolicyVersion` / `ListPolicyVersions` | `self-deploy.sh` Step 1 | checks whether `ekai-terraform-policy-infra`/`-cicd` already exist and whether their content has drifted, before deciding to create vs. version-bump |
| `iam:CreatePolicy` / `CreatePolicyVersion` / `DeletePolicyVersion` | `self-deploy.sh` Step 1 | creates the two policies on first run; publishes a new version if this repo's embedded policy document has changed since (IAM caps policies at 5 versions, so the oldest non-default is deleted first if needed) |
| `iam:GetUser` | both scripts | checks whether `ekai-terraform-<env>` already exists |
| `iam:CreateUser` | `self-deploy.sh` Step 1 | creates `ekai-terraform-<env>` on first run |
| `iam:AttachUserPolicy` | `self-deploy.sh` Step 1 | attaches both policies to the new user |
| `iam:ListAccessKeys` / `CreateAccessKey` / `DeleteAccessKey` / `UpdateAccessKey` | both scripts | every run mints a fresh access key for Terraform to use (deactivating/deleting old ones — IAM caps a user at 2 keys) |
| `iam:DetachUserPolicy` / `DeleteUser` | `self-deploy-destroy.sh` Section 5 (optional) | only reached if you opt into deleting `ekai-terraform-<env>` entirely during teardown |

## Why this had to be two identities in the first place

EKS clusters in this repo use `authentication_mode = CONFIG_MAP` — Kubernetes
RBAC access is granted *only* to the exact IAM identity that ran
`terraform apply` when the cluster was created (`aws-auth` ConfigMap, see
`modules/cluster/main.tf`). If Terraform ran as your own broad admin
identity, tearing down or modifying the cluster later from a different
machine, a different admin, or after that identity's credentials rotate
would all hit "Unauthorized" on every Kubernetes resource. A dedicated,
narrowly-scoped, script-managed identity sidesteps that entirely — anyone
who can run this script (with the permissions above) can also destroy what
it created, without needing to already have your original admin session.
