# terraform-aws-ekai

Deploy Ekai into **your own AWS account**. One script provisions the VPC, an
EKS cluster, RDS (PostgreSQL), in-cluster Redis/Neo4j, ArgoCD, and the
`ekai-saas` Helm chart — everything needed for a working Ekai install.

For how this repo is structured internally (why there are 2 Terraform
applies, the module layout), see [ARCHITECTURE.md](https://github.com/ekai-ai/terraform-aws-ekai/blob/main/ARCHITECTURE.md). This
doc only covers deploying it. Prefer consuming it directly as a module
instead of `self-deploy.sh`? See
[Using this as a Terraform Registry module](#using-this-as-a-terraform-registry-module)
below.

## Prerequisites

- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html),
  configured (`aws configure`) — see [PERMISSIONS.md](https://github.com/ekai-ai/terraform-aws-ekai/blob/main/PERMISSIONS.md) for
  exactly what this identity needs
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.9
- `jq`, `htpasswd` (from `apache2-utils`/`httpd-tools`), `openssl`
- A domain you can either delegate a subdomain of to Route53, or that
  already has a Route53 hosted zone

## Network Requirements

Only relevant if your VPC forces egress through a restrictive firewall
(common once an account sits behind a centralized egress VPC, Transit
Gateway, or third-party firewall appliance instead of a plain NAT gateway
to the internet). Give this list to whoever manages that firewall before
deploying — otherwise the EKS cluster and node group create successfully,
but the nodes never finish joining, or `terraform apply` hangs on a Helm
release with nothing pointing at the firewall as the cause. Running
`self-deploy.sh` from a machine *inside* that same restricted network?
Then both lists below apply to that one firewall, not just the cluster's.

This list is researched from
[AWS's own EKS security group documentation](https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html)
plus this repo's actual Terraform/Helm dependencies — unlike the Azure
version of this section, it has not been live-fire-tested against a real
restrictive firewall yet. Treat it as a solid starting point, not a
guarantee.

Also unlike Azure (nginx-ingress + cert-manager/Let's Encrypt), this repo
terminates TLS with an AWS Application Load Balancer
(`modules/alb_controller`) and an ACM certificate that's requested and
DNS-validated entirely inside AWS (`modules/bootstrap`, via Route53) — no
outbound ACME/Let's Encrypt call ever leaves the cluster.

**Machine running `self-deploy.sh`/`terraform apply`:** every AWS API call
Terraform and the AWS CLI make lands on a regional `*.amazonaws.com`
endpoint (STS, IAM, EC2, EKS, ELB, RDS, EFS, Secrets Manager, Route 53,
ACM, Auto Scaling, CloudWatch Logs, KMS) — AWS has no single management
endpoint the way Azure has `management.azure.com`, so allow
`*.amazonaws.com` rather than enumerating each service. Plus `github.com`,
`raw.githubusercontent.com`, `codeload.github.com` (cloning this repo),
`registry.terraform.io`, `releases.hashicorp.com` (Terraform itself and
its providers), `licensing.ekai.ai`, plus the Helm chart repos `terraform
apply` pulls directly: `argoproj.github.io` (ArgoCD), `aws.github.io`
(AWS Load Balancer Controller), `charts.external-secrets.io` (ESO),
`stakater.github.io` (Reloader), `kubernetes.github.io` (Cluster
Autoscaler), `kedacore.github.io` (KEDA), `helm.neo4j.com` (Neo4j), and
`registry-1.docker.io` (Bitnami Redis, pulled as an OCI chart).

**The EKS cluster (nodes + pods):**

| Destination | Port | Why |
| --- | --- | --- |
| Cluster security group (itself) | TCP 443, TCP 10250, TCP+UDP 53 | AWS's documented minimum once the default allow-all outbound rule is removed ([source](https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html)) |
| `*.<region>.eks.amazonaws.com` | HTTPS 443 | Node registration and cluster introspection at launch — AWS calls this out as required beyond the minimum rules above |
| `sts.amazonaws.com` | HTTPS 443 | IRSA — every pod assuming a role via its ServiceAccount (ALB Controller, Cluster Autoscaler, EBS/EFS CSI drivers, ESO, app pods) exchanges its OIDC token for AWS credentials here |
| `169.254.169.123` (link-local) | UDP 123 | Amazon Time Sync Service — built into every EC2 instance, needs no firewall rule at all (unlike AKS nodes, which need `UDP 123` to anywhere) |
| `api.ecr.<region>.amazonaws.com`, `*.dkr.ecr.<region>.amazonaws.com` | HTTPS 443 | Pulling the VPC CNI, CoreDNS, kube-proxy, EBS/EFS CSI driver, and CloudWatch Observability EKS add-on images — all hosted in AWS's own per-region ECR account |
| Amazon S3 (`s3.<region>.amazonaws.com`) | HTTPS 443 | ECR image layers are themselves stored in S3 — required to pull the add-on images above even though nothing in this stack uses S3 directly for its own images |
| `registry-1.docker.io` | HTTPS 443 | Bitnami Redis's and the Neo4j chart's own container images (both un-mirrored, pulled straight from Docker Hub) |
| `quay.io`, `ghcr.io`, `registry.k8s.io` | HTTPS 443 | Container images for ArgoCD, External Secrets Operator, Reloader, and Cluster Autoscaler/KEDA respectively |
| `public.ecr.aws` | HTTPS 443 | The `ekai-saas` Helm chart (pulled by ArgoCD from inside the cluster) + every app image, plus the AWS Load Balancer Controller's own image |
| `licensing.ekai.ai` | HTTPS 443 | Backend pod's own runtime license checks (not just the installer) |
| `api.github.com` | HTTPS 443 | GitHub code sync |

Only if you fill in the optional AWS-SES placeholders in the customer
secret: `email.<region>.amazonaws.com` (your own SES credentials) — skip
if you leave those `REPLACE_ME`.

## Deploy

```bash
git clone https://github.com/ekai-ai/terraform-aws-ekai.git
cd terraform-aws-ekai
cp env/customer.tfvars env/<name>.tfvars
```

`<name>` is your choice (e.g. client name) — it's both the filename and the
argument to `self-deploy.sh` below. Set `env` inside the file to the same
value. Don't edit `env/customer.tfvars` directly — it's the shared template.

**Required:** edit `env/<name>.tfvars` and set at minimum `region`, `env`,
`dns_zone` — `self-deploy.sh` won't work with placeholder values. Every
variable has an inline comment; worth a second look before your first
deploy:

| Variable | What it controls |
|---|---|
| `region` | AWS region everything is created in |
| `env` | Unique name embedded in every resource this creates — must be unique per deployment |
| `dns_zone` | Domain this deploys under (`portal.<dns_zone>`, `argocd.<dns_zone>`, ...) |

Full reference (every variable, every default): `variables.tf` and
`cicd/variables.tf` — or the Terraform Registry's auto-generated Inputs
page ([registry.terraform.io/modules/ekai-ai/ekai/aws](https://registry.terraform.io/modules/ekai-ai/ekai/aws)),
keeping in mind it may be behind `main` (see [above](#using-this-as-a-terraform-registry-module)).

```bash
./scripts/self-deploy.sh <name>
```

The argument to `self-deploy.sh` must match the tfvars filename in `env/`
(without `.tfvars`) — i.e. whatever you named the copy above. Use a real,
unique `env` value if you're deploying more than once — every AWS resource
this creates embeds `env` in its name, so re-running with the same value
modifies the *same* infrastructure rather than creating a second one.

`self-deploy.sh` creates the scoped IAM user Terraform needs, generates and
saves credentials, then runs both `terraform apply`s for you after one
confirmation (it creates real, billable AWS resources).

## After a successful deploy

Check the ArgoCD URL/password, Route53 nameservers, portal URL, and
customer secret's ARN:

```bash
terraform output -C examples/self-deploy/root
terraform output -C examples/self-deploy/cicd
```

## Tearing down

```bash
./scripts/self-deploy-destroy.sh <name>
```

Destroys everything this created, with confirmation prompts at each
destructive stage. Safe to re-run if it fails partway.

## Troubleshooting

**`InvalidClientTokenId` / `An error occurred ... The security token
included in the request is invalid` right at the start of the script** —
this means your *base* AWS credentials are broken, before the script even
gets to creating anything. Almost always caused by a stale
`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_SESSION_TOKEN` left
exported in your shell from an earlier, unrelated session (these
environment variables silently override your `~/.aws/credentials` file).
Check and clear them:

```bash
env | grep -i AWS_
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
aws sts get-caller-identity   # should succeed and show your real identity
```

Then re-run `self-deploy.sh`.

**`VcpuLimitExceeded` / node group stuck creating, or the EKS managed node
group's underlying Auto Scaling Group shows an `InsufficientInstanceCapacity`/
quota-related scaling error** — a fresh AWS account's default "Running
On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances" vCPU quota is often
far smaller than this stack's default node sizing needs (every node counts
against it, system and app node groups together). Request a quota increase
in the EC2 console (Service Quotas → Amazon EC2 → the relevant "Running
On-Demand ... instances" quota — usually auto-approved within minutes), or
lower `node_instance`/`node_min_size`/`mode_max_size` in that env's tfvars to
fit the existing quota.

## Using this as a Terraform Registry module

Already published:
[registry.terraform.io/modules/ekai-ai/ekai/aws](https://registry.terraform.io/modules/ekai-ai/ekai/aws).
**The published version can lag behind `main`** — publishing a new one
needs its own semver tag pushed, a separate step from merging to `main`;
check the Registry page's version/date against this repo's own commit
history before assuming it's current.

```hcl
module "infra" {
  source  = "registry.terraform.io/ekai-ai/ekai/aws"
  version = "~> 0.1"

  region = "us-east-1"
  env    = "acme"
  # ...every variable in variables.tf
}

module "cicd" {
  source  = "registry.terraform.io/ekai-ai/ekai/aws//cicd"
  version = "~> 0.1"
  # ...every variable in cicd/variables.tf, plus the values module.infra
  # exports that cicd needs (see examples/self-deploy/cicd/main.tf for
  # exactly which — with a registry module you'd normally wire these with
  # module.infra.X directly if both modules live in the same config, instead
  # of examples/self-deploy's terraform_remote_state indirection, which only
  # exists because self-deploy.sh's 2-apply split needs an actual state
  # boundary between them)
}
```

See [ARCHITECTURE.md](https://github.com/ekai-ai/terraform-aws-ekai/blob/main/ARCHITECTURE.md) for why this is 2 separate applies
and the full module layout.
