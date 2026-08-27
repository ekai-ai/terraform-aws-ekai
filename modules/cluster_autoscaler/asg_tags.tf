# The node group's ASG is created implicitly by aws_eks_node_group, not a
# first-class aws_autoscaling_group resource we own — aws_autoscaling_group_tag
# is the standard way to tag a pre-existing/externally-managed ASG. These two
# tags are what Cluster Autoscaler's --node-group-auto-discovery flag looks
# for, and what the IAM policy's Condition (iam.tf) scopes down to.
resource "aws_autoscaling_group_tag" "cluster_autoscaler_enabled" {
  count                  = var.enabled ? 1 : 0
  autoscaling_group_name = var.node_group_asg_name

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = false
  }
}

resource "aws_autoscaling_group_tag" "cluster_autoscaler_cluster_name" {
  count                  = var.enabled ? 1 : 0
  autoscaling_group_name = var.node_group_asg_name

  tag {
    key                 = "k8s.io/cluster-autoscaler/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = false
  }
}
