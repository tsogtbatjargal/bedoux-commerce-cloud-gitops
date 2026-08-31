#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/repo/scripts" "$test_root/repo/infra/terraform" \
  "$test_root/bin" "$test_root/tmp"
cp "$repo_root/scripts/terraform-session-destroy.sh" "$test_root/repo/scripts/"

cat > "$test_root/repo/scripts/terraform-persistent-state.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

cat > "$test_root/bin/aws" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *'sts get-caller-identity'*)
    printf '%s\n' 'TESTACCOUNT'
    ;;
  *'eks describe-cluster'*)
    printf '%s\n' 'https://oidc.eks.test.invalid/id/TEST'
    ;;
  *)
    printf 'unexpected aws invocation: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF

cat > "$test_root/bin/terraform" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == -chdir=* ]]; then
  shift
fi
case "${1:-}" in
  state)
    exit 0
    ;;
  plan)
    for arg in "$@"; do
      if [[ "$arg" == -out=* ]]; then
        printf '%s\n' 'mock-plan' > "${arg#-out=}"
        exit 0
      fi
    done
    printf '%s\n' 'missing -out argument' >&2
    exit 1
    ;;
  show)
    if [[ -n "${DESTROY_TEST_PLAN_JSON:-}" ]]; then
      printf '%s\n' "$DESTROY_TEST_PLAN_JSON"
    else
      printf '%s\n' '{"resource_changes":null}'
    fi
    ;;
  *)
    printf 'unexpected terraform invocation: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF

chmod +x "$test_root/repo/scripts/terraform-session-destroy.sh" \
  "$test_root/repo/scripts/terraform-persistent-state.sh" \
  "$test_root/bin/aws" "$test_root/bin/terraform"

env PATH="$test_root/bin:$PATH" TMPDIR="$test_root/tmp" \
  "$test_root/repo/scripts/terraform-session-destroy.sh" prepare --execute >/dev/null

oidc_file="$test_root/tmp/bedoux-session-destroy-oidc-provider-arn"
[[ "$(stat -c '%a' "$oidc_file")" == '600' ]]

plan_output="$test_root/no-op-plan.out"
(
  umask 022
  PATH="$test_root/bin:$PATH" TMPDIR="$test_root/tmp" \
    "$test_root/repo/scripts/terraform-session-destroy.sh" plan
) > "$plan_output"

plan_file="$test_root/tmp/bedoux-session-destroy.tfplan"
[[ "$(stat -c '%a' "$plan_file")" == '600' ]]
grep -Fq 'Saved temporary-only destroy plan:' "$plan_output"

persistent_output="$test_root/persistent-delete.out"
if env PATH="$test_root/bin:$PATH" TMPDIR="$test_root/tmp" \
  DESTROY_TEST_PLAN_JSON='{"resource_changes":[{"address":"module.ecr.aws_ecr_repository.this[\"bedoux-api\"]","change":{"actions":["delete"]}}]}' \
  "$test_root/repo/scripts/terraform-session-destroy.sh" plan > "$persistent_output" 2>&1; then
  printf '%s\n' 'persistent delete unexpectedly passed destroy-plan validation' >&2
  exit 1
fi
grep -Fq 'REFUSING: saved destroy plan includes persistent address prefix module.ecr.' \
  "$persistent_output"

printf '%s\n' 'terraform session destroy mocks OK'
