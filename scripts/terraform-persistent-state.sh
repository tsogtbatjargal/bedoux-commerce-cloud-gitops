#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/terraform-persistent-state.sh <import|detach> [--execute]

Imports or detaches the allowlisted ECR/IAM resources from the P6 session
state. The default is a dry run; pass --execute to modify Terraform state.

  import  Read existing allowlisted resources into the local Terraform state. The
          GitHub OIDC resources are imported only once P6.4 has created them.
  detach  Remove allowlisted resources from state before terraform destroy.

Neither command creates, modifies, or deletes AWS resources. Use from the
repository root after manually completing the AWS session preflight.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if (( $# < 1 || $# > 2 )); then
  usage >&2
  exit 2
fi

action="$1"
execute=false

if (( $# == 2 )); then
  if [[ "$2" != "--execute" ]]; then
    usage >&2
    exit 2
  fi
  execute=true
fi

if [[ "$action" != "import" && "$action" != "detach" ]]; then
  usage >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
terraform_dir="$repo_root/infra/terraform"

persistent_addresses=(
  'module.ecr.aws_ecr_lifecycle_policy.this["bedoux-api"]'
  'module.ecr.aws_ecr_lifecycle_policy.this["bedoux-web"]'
  'module.ecr.aws_ecr_repository.this["bedoux-api"]'
  'module.ecr.aws_ecr_repository.this["bedoux-web"]'
  'module.iam_cluster.aws_iam_role.cluster'
  'module.iam_cluster.aws_iam_role.node'
  'module.iam_cluster.aws_iam_role_policy_attachment.cluster'
  'module.iam_cluster.aws_iam_role_policy_attachment.node_cni'
  'module.iam_cluster.aws_iam_role_policy_attachment.node_ecr'
  'module.iam_cluster.aws_iam_role_policy_attachment.node_worker'
  'module.github_actions_oidc.aws_iam_openid_connect_provider.this'
  'module.github_actions_oidc.aws_iam_policy.deployment'
  'module.github_actions_oidc.aws_iam_role.this'
  'module.github_actions_oidc.aws_iam_role_policy_attachment.deployment'
  'module.workload_iam.aws_iam_policy.alb_controller'
  'module.workload_iam.aws_iam_role.alb_controller'
  'module.workload_iam.aws_iam_role.ebs_csi'
  'module.workload_iam.aws_iam_role_policy_attachment.alb_controller'
  'module.workload_iam.aws_iam_role_policy_attachment.ebs_csi'
)

run() {
  if "$execute"; then
    "$@"
  else
    printf 'DRY RUN:'
    printf ' %q' "$@"
    printf '\n'
  fi
}

if [[ "$action" == "detach" ]]; then
  run terraform -chdir="$terraform_dir" state rm "${persistent_addresses[@]}"
  exit 0
fi

if "$execute"; then
  task_account_id="$(aws sts get-caller-identity --profile bedoux-admin --query Account --output text)"
else
  task_account_id='<AWS_ACCOUNT_ID>'
fi

run terraform -chdir="$terraform_dir" import 'module.ecr.aws_ecr_repository.this["bedoux-api"]' bedoux-api
run terraform -chdir="$terraform_dir" import 'module.ecr.aws_ecr_repository.this["bedoux-web"]' bedoux-web
run terraform -chdir="$terraform_dir" import 'module.iam_cluster.aws_iam_role.cluster' bedoux-eks-cluster-role
run terraform -chdir="$terraform_dir" import 'module.iam_cluster.aws_iam_role.node' bedoux-eks-nodegroup-role

# The OIDC provider, role, and policy deliberately do not exist before P6.4's
# first apply. Importing them unconditionally would prevent that first session
# from reaching the apply which creates them. Later P6 sessions import them so
# detach/destroy continues to preserve the persistent no-hourly-cost identity
# resources.
github_oidc_provider_arn="arn:aws:iam::$task_account_id:oidc-provider/token.actions.githubusercontent.com"
github_deployment_policy_arn="arn:aws:iam::$task_account_id:policy/bedoux-github-actions-policy"

if ! "$execute"; then
  printf '%s\n' 'DRY RUN: conditionally import GitHub OIDC resources only when they already exist.'
elif aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn "$github_oidc_provider_arn" \
  --profile bedoux-admin >/dev/null 2>&1; then
  run terraform -chdir="$terraform_dir" import 'module.github_actions_oidc.aws_iam_openid_connect_provider.this' "$github_oidc_provider_arn"
else
  printf '%s\n' 'INFO: GitHub OIDC provider is absent; P6.4 Terraform apply will create it.'
fi

if ! "$execute"; then
  printf '%s\n' 'DRY RUN: conditionally import the GitHub Actions deployment role only when it already exists.'
elif aws iam get-role --role-name bedoux-github-actions-role --profile bedoux-admin >/dev/null 2>&1; then
  run terraform -chdir="$terraform_dir" import 'module.github_actions_oidc.aws_iam_role.this' bedoux-github-actions-role
else
  printf '%s\n' 'INFO: GitHub Actions deployment role is absent; P6.4 Terraform apply will create it.'
fi

if ! "$execute"; then
  printf '%s\n' 'DRY RUN: conditionally import the GitHub Actions deployment policy only when it already exists.'
elif aws iam get-policy --policy-arn "$github_deployment_policy_arn" --profile bedoux-admin >/dev/null 2>&1; then
  run terraform -chdir="$terraform_dir" import 'module.github_actions_oidc.aws_iam_policy.deployment' "$github_deployment_policy_arn"
else
  printf '%s\n' 'INFO: GitHub Actions deployment policy is absent; P6.4 Terraform apply will create it.'
fi

run terraform -chdir="$terraform_dir" import 'module.workload_iam.aws_iam_role.ebs_csi' bedoux-ebs-csi-role
run terraform -chdir="$terraform_dir" import 'module.workload_iam.aws_iam_role.alb_controller' bedoux-alb-controller-role
run terraform -chdir="$terraform_dir" import 'module.workload_iam.aws_iam_policy.alb_controller' "arn:aws:iam::$task_account_id:policy/bedoux-alb-controller-policy"
