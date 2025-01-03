# HCL to Create VPC, EKS Cluster  & Public Subnet
resource "aws_vpc" "main" {
    cidr_block = "10.0.0.0/16"
  }
# Define subnets in multiple Availability Zones
resource "aws_subnet" "public_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 4, count.index)
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[count.index]
}

# Data source to get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_eks_cluster" "eks_cluster" {
  name     = "quiz-app-cluster"
  role_arn = aws_iam_role.eks_role.arn

  vpc_config {
    subnet_ids = aws_subnet.public_subnet[*].id
  }
}
  # HCL to Create IAM Role for EKS
resource "aws_iam_role" "eks_role" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
    ]
  })
}

# Attach necessary policies to the EKS Role
resource "aws_iam_role_policy_attachment" "eks_policy_attachment" {
  role       = aws_iam_role.eks_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_service_policy_attachment" {
  role       = aws_iam_role.eks_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
}
