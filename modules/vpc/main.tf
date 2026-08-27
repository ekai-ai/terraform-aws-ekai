# create vpc
resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr
  #instance_tenancy     = "default"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name      = "${var.env}-vpc"
    ManagedBy = "Terraform"


  }
}

# create internet gateway and attach it to vpc
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name      = "${var.env}-igw"
    ManagedBy = "Terraform"
  }
}

# use data source to get all avalablility zones in region
data "aws_availability_zones" "available_zones" {}

resource "aws_subnet" "public_subnets" {
  vpc_id     = aws_vpc.vpc.id
  count      = length(var.public_subnet_cidrs)
  cidr_block = var.public_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available_zones.names[
    count.index % length(data.aws_availability_zones.available_zones.names)
  ]
  map_public_ip_on_launch = true

  tags = {
    Name                                                            = "${var.env}-public-${count.index + 1}"
    ManagedBy                                                       = "Terraform"
    "kubernetes.io/role/elb"                                        = "1"
    "kubernetes.io/cluster/${var.eks_cluster_name}-saas-${var.env}" = "shared"
  }
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }

  tags = {
    Name = "${var.env}-vpc-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public_subnets)
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public.id
}


resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_subnets[0].id

  # Explicit dep on IGW ensures correct destroy ordering:
  #   NAT GW deleted first (releases EIP + public-subnet ENI)
  #   → IGW detach succeeds (no more mapped public addresses)
  #   → public subnets delete cleanly (no more NAT GW ENI)
  # Without this, NAT GW and IGW destroy in parallel → IGW detach hits
  # "Network has mapped public address(es)" and subnets hit DependencyViolation.
  depends_on = [aws_internet_gateway.internet_gateway]

  tags = {
    Name = "${var.env}-vpc-nat"
  }
}


resource "aws_subnet" "private_subnets" {
  count      = length(var.private_subnet_cidrs)
  vpc_id     = aws_vpc.vpc.id
  cidr_block = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available_zones.names[
    count.index % length(data.aws_availability_zones.available_zones.names)
  ]

  tags = {
    Name                                                            = "${var.env}-private-${count.index + 1}"
    ManagedBy                                                       = "Terraform"
    "kubernetes.io/role/internal-elb"                               = "1"
    "kubernetes.io/cluster/${var.eks_cluster_name}-saas-${var.env}" = "shared"
  }
}
# Private Route Table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "${var.env}-vpc-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private_subnets)
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private.id
}
