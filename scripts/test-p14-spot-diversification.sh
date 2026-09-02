#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
terraform_dir="$repo_root/infra/terraform"
workflow="$repo_root/.github/workflows/pr-validation.yml"

profile_value() {
  awk -F= '/^[[:space:]]*node_instance_types[[:space:]]*=/{gsub(/[[:space:]]/, "", $2); print $2}' "$1"
}

assert_profile() {
  local profile="$1"
  local expected_desired="$2"
  local value

  value="$(profile_value "$profile")"
  test "$value" = '["t3.medium","t3a.medium"]'
  grep -Eq "^[[:space:]]*node_desired_size[[:space:]]*=[[:space:]]*$expected_desired[[:space:]]*$" "$profile"
  grep -Eq "^[[:space:]]*node_min_size[[:space:]]*=[[:space:]]*$expected_desired[[:space:]]*$" "$profile"
  grep -Eq "^[[:space:]]*node_max_size[[:space:]]*=[[:space:]]*$expected_desired[[:space:]]*$" "$profile"
}

assert_profile "$terraform_dir/terraform.tfvars.example" 1
assert_profile "$terraform_dir/terraform.tfvars.p11-ha.example" 2
grep -Eq '^[[:space:]]*default[[:space:]]*=.*\["t3.medium",[[:space:]]*"t3a.medium"\]' "$terraform_dir/variables.tf"
grep -Eq '^[[:space:]]*node_groups_per_az[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$terraform_dir/terraform.tfvars.p11-ha.example"

for test_file in eks_node_tagging ecr_lifecycle spot_diversification; do
  grep -Fq "terraform -chdir=infra/terraform test -filter=tests/$test_file.tftest.hcl -no-color" "$workflow"
done

printf '%s\n' 'P14.3 diversified Spot profiles, bounded scaling, and CI test wiring OK'
