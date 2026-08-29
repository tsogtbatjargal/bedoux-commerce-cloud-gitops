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
  instance_types          = ["t3.medium"]
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

run "primary_node_group_tagging" {
  command = plan

  module {
    source = "./modules/eks"
  }

  assert {
    condition = toset([
      for specification in aws_launch_template.this.tag_specifications : specification.resource_type
      ]) == toset(["instance", "volume"]) && alltrue([
      for specification in aws_launch_template.this.tag_specifications : (
        specification.tags["project"] == "bedoux-commerce-cloud" &&
        specification.tags["environment"] == "learning"
      )
    ])
    error_message = "The primary launch template must tag instances and volumes at creation."
  }

  assert {
    condition = (
      aws_launch_template.this.block_device_mappings[0].device_name == "/dev/xvda" &&
      aws_launch_template.this.block_device_mappings[0].ebs[0].volume_size == 20 &&
      aws_launch_template.this.block_device_mappings[0].ebs[0].volume_type == "gp3"
    )
    error_message = "The primary launch template must own the 20-GiB gp3 root-volume configuration."
  }

  assert {
    condition = alltrue([
      for resource in values(aws_autoscaling_group_tag.this) : resource.tag[0].propagate_at_launch
    ]) && toset(keys(aws_autoscaling_group_tag.this)) == toset(["project", "environment"])
    error_message = "The primary backing ASG must propagate both standard tags to future workers."
  }

  assert {
    condition     = length(aws_launch_template.secondary_az) == 0 && length(aws_eks_node_group.secondary_az) == 0
    error_message = "The default one-node profile must not create the P11 HA secondary path."
  }
}

run "p11_ha_node_group_tagging" {
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
    condition = toset([
      for specification in aws_launch_template.this.tag_specifications : specification.resource_type
      ]) == toset(["instance", "volume"]) && alltrue([
      for specification in aws_launch_template.this.tag_specifications : (
        specification.tags["project"] == "bedoux-commerce-cloud" &&
        specification.tags["environment"] == "learning"
      )
    ])
    error_message = "The P11 HA primary launch template must tag instances and volumes at creation."
  }

  assert {
    condition = toset([
      for specification in aws_launch_template.secondary_az[0].tag_specifications : specification.resource_type
      ]) == toset(["instance", "volume"]) && alltrue([
      for specification in aws_launch_template.secondary_az[0].tag_specifications : (
        specification.tags["project"] == "bedoux-commerce-cloud" &&
        specification.tags["environment"] == "learning"
      )
    ])
    error_message = "The P11 HA secondary launch template must tag instances and volumes at creation."
  }

  assert {
    condition = (
      aws_launch_template.secondary_az[0].block_device_mappings[0].device_name == "/dev/xvda" &&
      aws_launch_template.secondary_az[0].block_device_mappings[0].ebs[0].volume_size == 20 &&
      aws_launch_template.secondary_az[0].block_device_mappings[0].ebs[0].volume_type == "gp3"
    )
    error_message = "The P11 HA secondary launch template must own the 20-GiB gp3 root-volume configuration."
  }

  assert {
    condition = (
      alltrue([
        for resource in values(aws_autoscaling_group_tag.this) : resource.tag[0].propagate_at_launch
      ]) &&
      alltrue([
        for resource in values(aws_autoscaling_group_tag.secondary_az) : resource.tag[0].propagate_at_launch
      ]) &&
      toset(keys(aws_autoscaling_group_tag.this)) == toset(["project", "environment"]) &&
      toset(keys(aws_autoscaling_group_tag.secondary_az)) == toset(["project", "environment"])
    )
    error_message = "Both P11 HA backing ASGs must propagate both standard tags to future workers."
  }
}
