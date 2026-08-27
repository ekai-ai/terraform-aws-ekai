# ── EKS Cluster Role ──────────────────────────────────────────────────────────
# Only AmazonEKSClusterPolicy is needed by the control plane.
# ElasticLoadBalancingFullAccess removed — ALB management belongs to the
# ALB controller's IRSA role (modules/alb_controller/iam.tf), not here.
resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.env}-eks-role-${var.region}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "amazon_eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# ── EKS Node Group Role ───────────────────────────────────────────────────────
# CloudWatchFullAccess replaced with a scoped inline policy — nodes only need
# to PUT metrics and write log streams, not read/administer CloudWatch.
# ecr_pull_policy removed — AmazonEC2ContainerRegistryReadOnly already covers
# GetDownloadUrlForLayer, BatchGetImage, BatchCheckLayerAvailability, and
# GetAuthorizationToken so the duplicate inline policy is redundant.
resource "aws_iam_role" "nodes_general" {
  name = "${var.env}-node-group-role-${var.region}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "amazon_eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.nodes_general.name
}

resource "aws_iam_role_policy_attachment" "amazon_eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.nodes_general.name
}

resource "aws_iam_role_policy_attachment" "amazon_ec2_container_registry_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.nodes_general.name
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.nodes_general.name
}

# Scoped CloudWatch policy — nodes emit metrics + logs only.
resource "aws_iam_role_policy" "cloudwatch_node" {
  name = "${var.env}-cloudwatch-node-${var.region}"
  role = aws_iam_role.nodes_general.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
        ]
        Resource = "*"
      }
    ]
  })
}
