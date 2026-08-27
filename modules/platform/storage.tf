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
