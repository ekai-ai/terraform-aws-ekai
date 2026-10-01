# ── gp3 StorageClass — backed by the EBS CSI driver installed in 02-cluster ──
# Not marked as the cluster default: EKS's existing in-tree "gp2" class stays
# default so nothing already relying on it (e.g. Redis) is affected. PVCs that
# want gp3 (e.g. the ekai-saas Helm chart's ERD workspace volume) reference it
# by name explicitly.
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
  }

  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"

  parameters = {
    type = "gp3"
  }
}

# ── ERD workspace EFS filesystem ──────────────────────────────────────────────
# erd/erd-worker/document-worker/profile-worker share one scratch workspace.
# An EBS-backed (ReadWriteOnce) PVC only ever attaches to one node at a time --
# any rollout that spreads those pods across nodes deadlocks with Multi-Attach
# errors (confirmed live on the GCP side before its equivalent GCS FUSE fix).
# EFS is ReadWriteMany -- no such limit. Access is controlled by the security
# group (NFS from inside the VPC only) and the access point's POSIX
# permissions below, not per-workload IAM -- the EFS CSI driver's own
# cluster-wide IRSA role (modules/efs_csi_driver) covers every pod that mounts
# it, same as the EBS CSI driver already does for gp3 PVCs.
resource "aws_efs_file_system" "erd_workspace" {
  creation_token = "${var.env}-erd-workspace"
  encrypted      = true

  tags = {
    Name    = "${var.env}-erd-workspace"
    managed = "terraform"
  }
}

resource "aws_security_group" "efs" {
  name        = "${var.env}-erd-workspace-efs-sg"
  description = "Allow NFS to the ERD workspace EFS filesystem from within the VPC only"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "NFS from within the VPC only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.env}-erd-workspace-efs-sg", managed = "Terraform" }
}

# One mount target per private subnet -- EFS is regional, but each AZ's nodes
# need a mount target in their own subnet to reach it.
resource "aws_efs_mount_target" "erd_workspace" {
  count           = length(var.private_subnet_ids)
  file_system_id  = aws_efs_file_system.erd_workspace.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

# uid/gid 10000 matches the GCP side's GCS FUSE mount options -- same
# convention, both are just "some non-root uid the ERD containers run as".
resource "aws_efs_access_point" "erd_workspace" {
  file_system_id = aws_efs_file_system.erd_workspace.id

  posix_user {
    uid = 10000
    gid = 10000
  }

  root_directory {
    path = "/erd-workspace"
    creation_info {
      owner_uid   = 10000
      owner_gid   = 10000
      permissions = "775"
    }
  }

  tags = { Name = "${var.env}-erd-workspace-ap", managed = "terraform" }

  # Mount targets must exist before anything can actually use the access
  # point -- not a hard API dependency, but avoids a pod trying to mount
  # before there's a network path to do so.
  depends_on = [aws_efs_mount_target.erd_workspace]
}
