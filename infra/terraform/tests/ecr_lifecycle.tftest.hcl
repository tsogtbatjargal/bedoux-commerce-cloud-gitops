mock_provider "aws" {}

variables {
  repository_names = ["bedoux-api", "bedoux-web"]
  tags = {
    project     = "bedoux-commerce-cloud"
    environment = "learning"
  }
}

run "deployment_tags_are_lifecycle_managed" {
  command = plan

  module {
    source = "./modules/ecr"
  }

  assert {
    condition = alltrue([
      for policy in values(aws_ecr_lifecycle_policy.this) : (
        jsondecode(policy.policy).rules[0].selection.tagStatus == "tagged" &&
        jsondecode(policy.policy).rules[0].selection.tagPatternList == ["*"] &&
        !contains(keys(jsondecode(policy.policy).rules[0].selection), "tagPrefixList")
      )
    ])
    error_message = "The tagged-image lifecycle rule must match the bare commit-SHA tags emitted by deployment CI."
  }
}
