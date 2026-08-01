#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/terraform-session-destroy.sh <plan|apply> [--execute]

Safely destroys only temporary P6 EKS-session infrastructure while preserving
the persistent ECR and IAM allowlist. Run only inside an active AWS session.

  plan             Reads the live cluster OIDC issuer and writes a saved,
                   targeted Terraform destroy plan under /tmp.
  apply --execute  Applies that saved plan, deletes the now-orphaned cluster
                   OIDC provider by its exact captured ARN, and detaches the
                   persistent allowlist from Terraform state.

The plan intentionally targets only EKS, its add-on/access entries, and the
VPC. It never targets the workload-IAM module: targeting its OIDC provider can
pull persistent IRSA roles into a destroy graph.
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

if [[ "$action" != "plan" && "$action" != "apply" ]]; then
  usage >&2
  exit 2
fi

if [[ "$action" == "apply" ]]; then
  if (( $# != 2 )) || [[ "$2" != "--execute" ]]; then
    usage >&2
    exit 2
  fi
  execute=true
elif (( $# != 1 )); then
  usage >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
terraform_dir="$repo_root/infra/terraform"
plan_file="${TMPDIR:-/tmp}/bedoux-session-destroy.tfplan"
oidc_file="${TMPDIR:-/tmp}/bedoux-session-destroy-oidc-provider-arn"

temporary_targets=(
  module.addons
  module.eks
  module.vpc
)

persistent_prefixes=(
  'module.ecr.'
  'module.iam_cluster.'
  'module.github_actions_oidc.'
  'module.workload_iam.aws_iam_role.'
  'module.workload_iam.aws_iam_policy.'
  'module.workload_iam.aws_iam_role_policy_attachment.'
)

if [[ "$action" == "plan" ]]; then
  task_account_id="$(aws sts get-caller-identity --profile bedoux-admin --query Account --output text)"
  cluster_oidc_issuer="$(aws eks describe-cluster --profile bedoux-admin --region ca-central-1 \
    --name bedoux --query 'cluster.identity.oidc.issuer' --output text)"
  test -n "$cluster_oidc_issuer"
  test "$cluster_oidc_issuer" != "None"
  printf 'arn:aws:iam::%s:oidc-provider/%s\n' "$task_account_id" "${cluster_oidc_issuer#https://}" > "$oidc_file"
  unset task_account_id cluster_oidc_issuer

  target_args=()
  for target in "${temporary_targets[@]}"; do
    target_args+=("-target=$target")
  done

  terraform -chdir="$terraform_dir" plan -destroy "${target_args[@]}" -out="$plan_file"

  planned_deletes="$(terraform -chdir="$terraform_dir" show -json "$plan_file" | jq -r \
    '.resource_changes[] | select(.change.actions == ["delete"]) | .address')"
  for prefix in "${persistent_prefixes[@]}"; do
    if grep -Fq "${prefix}" <<<"$planned_deletes"; then
      printf 'REFUSING: saved destroy plan includes persistent address prefix %s\n' "$prefix" >&2
      exit 1
    fi
  done

  printf 'Saved temporary-only destroy plan: %s\n' "$plan_file"
  printf 'Captured cluster OIDC provider for explicit post-cluster deletion.\n'
  exit 0
fi

test -f "$plan_file"
test -s "$oidc_file"
terraform -chdir="$terraform_dir" apply "$plan_file"

cluster_oidc_provider_arn="$(<"$oidc_file")"
aws iam delete-open-id-connect-provider --profile bedoux-admin \
  --open-id-connect-provider-arn "$cluster_oidc_provider_arn"
unset cluster_oidc_provider_arn

terraform -chdir="$terraform_dir" state rm \
  module.workload_iam.aws_iam_openid_connect_provider.this
"$repo_root/scripts/terraform-persistent-state.sh" detach --execute

printf 'Temporary session infrastructure destroyed; persistent allowlist detached.\n'
