output "asg_name" {
  description = "Name of the Auto Scaling Group EKS created behind this managed node group"
  value       = aws_eks_node_group.nodes_general.resources[0].autoscaling_groups[0].name
}
