#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/terraform-session-destroy.sh <prepare|plan|apply> [--execute]

Safely destroys only temporary EKS-session infrastructure while preserving
the persistent ECR and IAM allowlist. Run only inside an active AWS session.

  prepare          Dry-runs the state-only preparation needed before planning.
  prepare --execute Captures the live cluster OIDC provider, then detaches the
                   persistent allowlist and cluster OIDC provider from Terraform
                   state. It never changes AWS resources.
  plan             Writes a saved, targeted Terraform destroy plan under /tmp.
  apply --execute  Applies that saved plan and deletes the now-orphaned cluster
                   OIDC provider by its exact captured ARN.

Run prepare --execute before plan. Detaching state first keeps Terraform's
targeted destroy graph limited to EKS, RDS, P7 managed-data modules, its add-on/access entries, and the VPC;
otherwise the cluster OIDC dependency can pull persistent IRSA roles into it.
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

if [[ "$action" != "prepare" && "$action" != "plan" && "$action" != "apply" ]]; then
  usage >&2
  exit 2
fi

if [[ "$action" == "prepare" ]]; then
  if (( $# == 2 )) && [[ "$2" == "--execute" ]]; then
    execute=true
  elif (( $# != 1 )); then
    usage >&2
    exit 2
  fi
elif [[ "$action" == "apply" ]]; then
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
  module.rds
  module.product_images
  module.database_secrets
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

if [[ "$action" == "prepare" ]]; then
  task_account_id="$(aws sts get-caller-identity --profile bedoux-admin --query Account --output text)"
  cluster_oidc_issuer="$(aws eks describe-cluster --profile bedoux-admin --region ca-central-1 \
    --name bedoux --query 'cluster.identity.oidc.issuer' --output text)"
  test -n "$cluster_oidc_issuer"
  test "$cluster_oidc_issuer" != "None"
  cluster_oidc_provider_arn="arn:aws:iam::${task_account_id}:oidc-provider/${cluster_oidc_issuer#https://}"
  unset task_account_id cluster_oidc_issuer

  if ! "$execute"; then
    printf '%s\n' 'DRY RUN: capture the cluster OIDC provider and detach persistent Terraform state.'
    "$repo_root/scripts/terraform-persistent-state.sh" detach
    printf 'DRY RUN: terraform -chdir=%q state rm %q\n' \
      "$terraform_dir" 'module.workload_iam.aws_iam_openid_connect_provider.this'
    unset cluster_oidc_provider_arn
    exit 0
  fi

  printf '%s\n' "$cluster_oidc_provider_arn" > "$oidc_file"
  unset cluster_oidc_provider_arn
  "$repo_root/scripts/terraform-persistent-state.sh" detach --execute
  if terraform -chdir="$terraform_dir" state list | grep -Fxq \
    'module.workload_iam.aws_iam_openid_connect_provider.this'; then
    terraform -chdir="$terraform_dir" state rm \
      module.workload_iam.aws_iam_openid_connect_provider.this
  else
    printf '%s\n' 'INFO: cluster OIDC provider is already detached from Terraform state.'
  fi
  printf '%s\n' 'Persistent Terraform state detached; ready to create the temporary-only destroy plan.'
  exit 0
fi

if [[ "$action" == "plan" ]]; then
  test -s "$oidc_file"

  target_args=()
  for target in "${temporary_targets[@]}"; do
    target_args+=("-target=$target")
  done

  # P7.2's image bucket is optional in the normal learning profile. Keep its
  # module explicitly instantiated for a destruction-only plan whenever its
  # bucket is present in state.
  product_images_var_args=()
  if terraform -chdir="$terraform_dir" state list | grep -Fxq \
    'module.product_images[0].aws_s3_bucket.this'; then
    product_images_var_args+=("-var=s3_images_enabled=true")
    printf '%s\n' 'INFO: including the P7.2 product-images module present in Terraform state.'
  fi

  secrets_manager_var_args=()
  if terraform -chdir="$terraform_dir" state list | grep -Fxq \
    'module.database_secrets[0].aws_secretsmanager_secret.this'; then
    secrets_manager_var_args+=("-var=secrets_manager_enabled=true" "-var=rds_enabled=true")
    printf '%s\n' 'INFO: including the P7.3 database secret module present in Terraform state.'
  fi

  terraform -chdir="$terraform_dir" plan -destroy "${target_args[@]}" \
    "${product_images_var_args[@]}" "${secrets_manager_var_args[@]}" -out="$plan_file"

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

printf 'Temporary session infrastructure destroyed; persistent allowlist detached.\n'
