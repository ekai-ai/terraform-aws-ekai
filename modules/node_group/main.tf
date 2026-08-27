resource "aws_eks_node_group" "nodes_general" {
  cluster_name    = var.eks_cluster_name
  node_group_name = "${var.eks_cluster_name}-NG"
  node_role_arn   = var.NODE_GROUP_ARN

  subnet_ids = var.private_subnet_ids

  scaling_config {
    desired_size = var.node_min_size
    max_size     = var.mode_max_size
    min_size     = var.node_min_size
  }


  ami_type = var.ami_type

  # Disk size in GiB for worker nodes
  disk_size = var.node_disk_size

  # List of instance types associated with the eks Node Group
  instance_types = [var.node_instance]
  update_config {
    max_unavailable_percentage = 50
  }

  # Ensure that iam Role permissions are created before and deleted after eks Node Group handling.
  # Otherwise, eks will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  # depends_on = [
  #   aws_iam_role_policy_attachment.amazon_eks_worker_node_policy_general,
  #   aws_iam_role_policy_attachment.amazon_eks_cni_policy_general,
  #   aws_iam_role_policy_attachment.amazon_ec2_container_registry_read_only,
  # ]
  tags = {
    Name    = "node-group-${var.eks_cluster_name}"
    managed = "terraform"
  }
}