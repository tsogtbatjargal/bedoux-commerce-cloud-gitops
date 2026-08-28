#!/usr/bin/env bash

set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  printf '%s\n' 'Usage: scripts/test-p13-alb-pod-readiness-gate.sh'
  printf '%s\n' 'Runs local command mocks; contacts no Kubernetes endpoint.'
  exit 0
fi
if (($# != 0)); then
  exit 2
fi

fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT

cat >"$fixture_dir/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${MOCK_MODE:-healthy}" in
  healthy)
    printf '%s\n' '{"items":[{"metadata":{"name":"web-new"},"spec":{"readinessGates":[{"conditionType":"target-health.elbv2.k8s.aws/mock"}]},"status":{"phase":"Running","conditions":[{"type":"Ready","status":"True"},{"type":"target-health.elbv2.k8s.aws/mock","status":"True"}]}},{"metadata":{"name":"web-old","deletionTimestamp":"2026-08-27T00:00:00Z"},"spec":{},"status":{"phase":"Running","conditions":[]}}]}'
    ;;
  missing)
    printf '%s\n' '{"items":[{"metadata":{"name":"web"},"spec":{},"status":{"phase":"Running","conditions":[{"type":"Ready","status":"True"}]}}]}'
    ;;
  unhealthy)
    printf '%s\n' '{"items":[{"metadata":{"name":"web"},"spec":{"readinessGates":[{"conditionType":"target-health.elbv2.k8s.aws/mock"}]},"status":{"phase":"Running","conditions":[{"type":"Ready","status":"False"},{"type":"target-health.elbv2.k8s.aws/mock","status":"False"}]}}]}'
    ;;
esac
EOF
chmod +x "$fixture_dir/kubectl"

PATH="$fixture_dir:$PATH" MOCK_MODE=healthy \
  scripts/p13-alb-pod-readiness-gate.sh --context mock-eks --execute >/dev/null

for mode in missing unhealthy; do
  if PATH="$fixture_dir:$PATH" MOCK_MODE="$mode" \
    scripts/p13-alb-pod-readiness-gate.sh --context mock-eks --execute >/dev/null 2>&1; then
    printf 'expected %s ALB pod readiness contract to fail closed\n' "$mode" >&2
    exit 1
  fi
done

printf '%s\n' 'P13 ALB pod readiness mock tests passed.'
