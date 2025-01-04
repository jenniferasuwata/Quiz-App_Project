#######################################
# 1. VPC & Subnets
#######################################
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

# Data source to get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# Define subnets in multiple Availability Zones
resource "aws_subnet" "public_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 4, count.index)
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[count.index]
}

#######################################
# 2. IAM Role for the EKS Cluster
#######################################
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

# Attach necessary policies to the EKS Cluster Role
resource "aws_iam_role_policy_attachment" "eks_policy_attachment" {
  role       = aws_iam_role.eks_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_service_policy_attachment" {
  role       = aws_iam_role.eks_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
}

#######################################
# 3. EKS Cluster
#######################################
resource "aws_eks_cluster" "eks_cluster" {
  name     = "quiz-app-cluster"
  role_arn = aws_iam_role.eks_role.arn

  vpc_config {
    subnet_ids = aws_subnet.public_subnet[*].id
  }
}


#######################################
# 4. IAM Role for the Node Group (EC2)
#######################################
resource "aws_iam_role" "eks_node_role" {
  name = "eks-nodegroup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
    ]
  })
}

# Attach necessary policies to the Node Role
resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

#######################################
# 5. EKS Node Group
#######################################
resource "aws_eks_node_group" "jenkins_server" {
  # IMPORTANT: Use the cluster resource reference here
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "jenkins_node"

  # Use the *node* role (trusts ec2.amazonaws.com)
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = aws_subnet.public_subnet[*].id

  scaling_config {
    desired_size = 2
    max_size     = 5
    min_size     = 1
  }

  instance_types = ["t3.medium"]

  # Ensure policies are attached before creating the node group
  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly
  ]
}
#######################################
# 6. Networking for Public Subnets
#######################################

# 6.1 Create an Internet Gateway
resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main.id
}

# 6.2 Create a Route Table for Public Traffic
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id
}

# 6.3 Create a default route to the Internet Gateway
resource "aws_route" "public_route" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main_igw.id
}

# 6.4 Associate subnets with the public route table
resource "aws_route_table_association" "public_rta" {
  count          = length(aws_subnet.public_subnet[*].id)
  subnet_id      = element(aws_subnet.public_subnet[*].id, count.index)
  route_table_id = aws_route_table.public_route_table.id
}
