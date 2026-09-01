mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      arn = "arn:aws:iam::aws:root"
    }
  }
}

variables {
  cluster_name            = "bedoux"
  kubernetes_version      = "1.34"
  subnet_ids              = ["subnet-primary", "subnet-secondary"]
  cluster_role_arn        = "arn:aws:iam::aws:role/bedoux-cluster"
  node_role_arn           = "arn:aws:iam::aws:role/bedoux-node"
  github_actions_role_arn = "arn:aws:iam::aws:role/bedoux-github"
  instance_types          = ["t3.medium", "t3a.medium"]
  capacity_type           = "SPOT"
  node_groups_per_az      = false
  desired_size            = 1
  min_size                = 1
  max_size                = 1
  disk_size_gib           = 20
  tags = {
    project     = "bedoux-commerce-cloud"
    environment = "learning"
  }
}

run "spot_pool_is_diversified_and_bounded" {
  command = plan

  module {
    source = "./modules/eks"
  }

  assert {
    condition     = toset(aws_eks_node_group.this.instance_types) == toset(["t3.medium", "t3a.medium"])
    error_message = "The default Spot node group must retain both same-shape instance types."
  }

  assert {
    condition = (
      aws_eks_node_group.this.capacity_type == "SPOT" &&
      aws_eks_node_group.this.scaling_config[0].min_size == 1 &&
      aws_eks_node_group.this.scaling_config[0].desired_size == 1 &&
      aws_eks_node_group.this.scaling_config[0].max_size == 1
    )
    error_message = "Spot diversification must not change the bounded one-node profile."
  }

  assert {
    condition = (
      length(aws_eks_node_group.secondary_az) == 0 &&
      length(aws_launch_template.secondary_az) == 0
    )
    error_message = "The default diversified profile must not create the P11 HA secondary path."
  }
}

run "p11_ha_spot_pool_is_diversified_and_bounded" {
  command = plan

  module {
    source = "./modules/eks"
  }

  variables {
    node_groups_per_az = true
    desired_size       = 2
    min_size           = 2
    max_size           = 2
  }

  assert {
    condition = (
      toset(aws_eks_node_group.this.instance_types) == toset(["t3.medium", "t3a.medium"]) &&
      toset(aws_eks_node_group.secondary_az[0].instance_types) == toset(["t3.medium", "t3a.medium"])
    )
    error_message = "Both P11 HA Spot groups must retain the diversified same-shape pool."
  }

  assert {
    condition = (
      aws_eks_node_group.this.scaling_config[0].min_size == 1 &&
      aws_eks_node_group.this.scaling_config[0].desired_size == 1 &&
      aws_eks_node_group.this.scaling_config[0].max_size == 1 &&
      aws_eks_node_group.secondary_az[0].scaling_config[0].min_size == 1 &&
      aws_eks_node_group.secondary_az[0].scaling_config[0].desired_size == 1 &&
      aws_eks_node_group.secondary_az[0].scaling_config[0].max_size == 1
    )
    error_message = "P11 HA diversification must retain one node per AZ and the aggregate two-node cap."
  }
}
