#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/verify-iam-boundary.sh [--execute]

Verifies ADR 0015 after the owner has applied bedoux-iam-scoped v4:

  - every persistent Bedoux role has the required PowerUserAccess boundary;
  - the live bedoux-iam-scoped default document exactly matches the committed v4;
  - creating an unbounded Bedoux role is rejected by an explicit deny.

The default is a no-write preview. --execute performs read-only checks and one
bounded negative create-role attempt that must fail without creating a role.
Run --execute only inside an active AWS session after completing the manual
preflight in docs/runbooks/aws-session.md.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if (( $# > 1 )) || { (( $# == 1 )) && [[ "$1" != "--execute" ]]; }; then
  usage >&2
  exit 2
fi

execute=false
if [[ "${1:-}" == "--execute" ]]; then
  execute=true
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
expected_policy="$repo_root/infra/iam/bedoux-iam-scoped-v4.json"
negative_trust="$repo_root/infra/iam/negative-test-trust-policy.json"
required_boundary="arn:aws:iam::aws:policy/PowerUserAccess"
negative_role="bedoux-boundary-negative-test"
profile="bedoux-admin"

roles=(
  bedoux-eks-cluster-role
  bedoux-eks-nodegroup-role
  bedoux-ebs-csi-role
  bedoux-vpc-cni-role
  bedoux-alb-controller-role
  bedoux-github-actions-role
)

if ! "$execute"; then
  printf 'DRY RUN: verify boundary %s on %d exact roles.\n' "$required_boundary" "${#roles[@]}"
  printf '%s\n' 'DRY RUN: compare the live bedoux-iam-scoped default version with infra/iam/bedoux-iam-scoped-v4.json.'
  printf 'DRY RUN: require an explicit AccessDenied for creating %s without a boundary.\n' "$negative_role"
  exit 0
fi

for role in "${roles[@]}"; do
  live_boundary="$(aws iam get-role --profile "$profile" --role-name "$role" \
    --query 'Role.PermissionsBoundary.PermissionsBoundaryArn' --output text)"
  if [[ "$live_boundary" != "$required_boundary" ]]; then
    printf 'FAIL: role %s does not have the required boundary.\n' "$role" >&2
    exit 1
  fi
  printf 'PASS: required boundary is attached to %s.\n' "$role"
done

task_account_id="${BEDOUX_ACCOUNT_ID:-}"
if [[ -z "$task_account_id" ]]; then
  task_account_id="$(aws sts get-caller-identity --profile "$profile" --query Account --output text)"
fi
scoped_policy_arn="arn:aws:iam::${task_account_id}:policy/bedoux-iam-scoped"
default_version="$(aws iam get-policy --profile "$profile" --policy-arn "$scoped_policy_arn" \
  --query 'Policy.DefaultVersionId' --output text)"

task_tmp_dir="$(mktemp -d)"
task_policy_path="$task_tmp_dir/live-policy.json"
task_error_path="$task_tmp_dir/negative-test.err"
cleanup() {
  rm -f "$task_policy_path" "$task_error_path"
  rmdir "$task_tmp_dir"
}
trap cleanup EXIT

aws iam get-policy-version --profile "$profile" --policy-arn "$scoped_policy_arn" \
  --version-id "$default_version" --query 'PolicyVersion.Document' --output json > "$task_policy_path"

if ! diff -u <(jq -S . "$expected_policy") <(jq -S . "$task_policy_path") >/dev/null; then
  printf '%s\n' 'FAIL: live bedoux-iam-scoped default version does not match committed v4.' >&2
  exit 1
fi
printf '%s\n' 'PASS: live bedoux-iam-scoped default version matches committed v4.'

if aws iam get-role --profile "$profile" --role-name "$negative_role" >/dev/null 2>&1; then
  printf 'REFUSING: negative-test role %s already exists.\n' "$negative_role" >&2
  exit 1
fi

if aws iam create-role --profile "$profile" --role-name "$negative_role" \
  --assume-role-policy-document "file://$negative_trust" > /dev/null 2> "$task_error_path"; then
  printf '%s\n' 'FAIL: unbounded role creation unexpectedly succeeded.' >&2
  printf 'OWNER ACTION REQUIRED: delete exact role %s in the admin console; v4 intentionally prevents the project operator from managing an unbounded role.\n' "$negative_role" >&2
  exit 1
fi

if ! grep -q 'AccessDenied' "$task_error_path" || ! grep -qi 'explicit deny' "$task_error_path"; then
  printf '%s\n' 'FAIL: role creation failed, but not with the expected explicit AccessDenied.' >&2
  exit 1
fi

printf '%s\n' 'PASS: unbounded Bedoux role creation was rejected by an explicit deny; no test role exists.'
