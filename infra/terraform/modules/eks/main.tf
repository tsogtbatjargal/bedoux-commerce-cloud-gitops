resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = var.cluster_role_arn
  version  = var.kubernetes_version

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  vpc_config {
    endpoint_private_access = false
    endpoint_public_access  = true
    subnet_ids              = var.subnet_ids
  }

  tags = var.tags
}

data "aws_caller_identity" "current" {}

resource "aws_eks_access_entry" "cluster_creator" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = data.aws_caller_identity.current.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "cluster_creator_admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.cluster_creator.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

# CI can deploy only into the application namespace. The namespace itself is an
# explicit P6.4 session precondition, so the GitHub role does not need cluster-wide
# administrative access merely to bootstrap it.
resource "aws_eks_access_entry" "github_actions" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.github_actions_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "github_actions_edit" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.github_actions.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = ["bedoux"]
  }
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = var.node_groups_per_az ? "${var.cluster_name}-ng-spot-a" : "${var.cluster_name}-ng-spot"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.node_groups_per_az ? [var.subnet_ids[0]] : var.subnet_ids

  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = var.capacity_type
  disk_size      = var.disk_size_gib
  instance_types = var.instance_types

  scaling_config {
    desired_size = var.node_groups_per_az ? 1 : var.desired_size
    min_size     = var.node_groups_per_az ? 1 : var.min_size
    max_size     = var.node_groups_per_az ? 1 : var.max_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = var.tags

  lifecycle {
    precondition {
      condition = !var.node_groups_per_az || (
        length(var.subnet_ids) == 2 &&
        var.desired_size == 2 &&
        var.min_size == 2 &&
        var.max_size == 2
      )
      error_message = "node_groups_per_az requires exactly two subnets and aggregate desired/min/max values fixed at 2."
    }
  }

  depends_on = [aws_eks_cluster.this]
}

# P11.4 opt-in only. A single multi-subnet Spot node group placed both P11.3
# nodes in one AZ. Pinning one fixed-size group to each subnet makes the healthy
# cross-AZ baseline deterministic without increasing the two-node cost ceiling.
resource "aws_eks_node_group" "secondary_az" {
  count = var.node_groups_per_az ? 1 : 0

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-ng-spot-b"
  node_role_arn   = var.node_role_arn
  subnet_ids      = [var.subnet_ids[1]]

  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = var.capacity_type
  disk_size      = var.disk_size_gib
  instance_types = var.instance_types

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  tags = var.tags

  depends_on = [aws_eks_cluster.this]
}
