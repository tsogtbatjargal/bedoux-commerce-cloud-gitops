#!/usr/bin/env bash

set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  printf '%s\n' 'Usage: scripts/test-p13-alb-reconciliation-gate.sh'
  printf '%s\n' 'Runs local command mocks; contacts neither AWS nor Kubernetes.'
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
joined="$*"
case "$joined" in
  *"get ingress bedoux"*"spec.ingressClassName"*)
    printf '%s' 'alb'
    ;;
  *"get ingress bedoux"*"status.loadBalancer"*)
    printf '%s' 'mock.ca-central-1.elb.amazonaws.com'
    ;;
  *"get targetgroupbindings.elbv2.k8s.aws"*)
    if [[ "${MOCK_MODE:-staged}" == "cleanup" ]]; then
      printf '%s\n' '{"items":[{"spec":{"serviceRef":{"name":"web"},"targetGroupARN":"arn:stable"}}]}'
    else
      printf '%s\n' '{"items":[{"spec":{"serviceRef":{"name":"web"},"targetGroupARN":"arn:stable"}},{"spec":{"serviceRef":{"name":"web-canary"},"targetGroupARN":"arn:canary"}}]}'
    fi
    ;;
  *)
    exit 1
    ;;
esac
EOF

cat >"$fixture_dir/aws" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
operation="${2:-}"
case "$operation" in
  describe-load-balancers)
    printf '%s\n' '{"LoadBalancers":[{"DNSName":"mock.ca-central-1.elb.amazonaws.com","Type":"application","State":{"Code":"active"},"LoadBalancerArn":"arn:lb"}]}'
    ;;
  describe-listeners)
    printf '%s\n' '{"Listeners":[{"ListenerArn":"arn:listener"}]}'
    ;;
  describe-rules)
    if [[ "${MOCK_RULE_MODE:-${MOCK_MODE:-staged}}" == "cleanup" ]]; then
      # Live AWS normalizes a sole forward target to relative weight 1.
      printf '%s\n' '{"Rules":[{"Actions":[{"Type":"forward","TargetGroupArn":"arn:stable","ForwardConfig":{"TargetGroups":[{"TargetGroupArn":"arn:stable","Weight":1}]}}]}]}'
    elif [[ "${MOCK_RULE_MODE:-${MOCK_MODE:-staged}}" == "cleanup-declared" ]]; then
      printf '%s\n' '{"Rules":[{"Actions":[{"Type":"forward","ForwardConfig":{"TargetGroups":[{"TargetGroupArn":"arn:stable","Weight":100}]}}]}]}'
    elif [[ "${MOCK_RULE_MODE:-${MOCK_MODE:-staged}}" == "cleanup-zero" ]]; then
      printf '%s\n' '{"Rules":[{"Actions":[{"Type":"forward","TargetGroupArn":"arn:stable","ForwardConfig":{"TargetGroups":[{"TargetGroupArn":"arn:stable","Weight":0}]}}]}]}'
    elif [[ "${MOCK_RULE_MODE:-${MOCK_MODE:-staged}}" == "promotion" ]]; then
      printf '%s\n' '{"Rules":[{"Actions":[{"Type":"forward","ForwardConfig":{"TargetGroups":[{"TargetGroupArn":"arn:stable","Weight":100},{"TargetGroupArn":"arn:canary","Weight":0}]}}]}]}'
    else
      printf '%s\n' '{"Rules":[{"Actions":[{"Type":"forward","ForwardConfig":{"TargetGroups":[{"TargetGroupArn":"arn:stable","Weight":90},{"TargetGroupArn":"arn:canary","Weight":10}]}}]}]}'
    fi
    ;;
  describe-target-group-attributes)
    if [[ "${MOCK_ATTRIBUTES_MODE:-}" == "malformed" ]]; then
      # A shape AWS should never actually return -- proves a harness error, not a
      # target group that simply hasn't reconciled its attribute yet.
      printf '%s\n' '{"NotAttributes":[]}'
    else
      printf '{"Attributes":[{"Key":"deregistration_delay.timeout_seconds","Value":"%s"}]}\n' \
        "${MOCK_DEREGISTRATION_DELAY_SECONDS:-30}"
    fi
    ;;
  describe-target-health)
    printf '%s\n' '{"TargetHealthDescriptions":[{"TargetHealth":{"State":"healthy"}}]}'
    ;;
  *)
    exit 1
    ;;
esac
EOF

chmod +x "$fixture_dir/kubectl" "$fixture_dir/aws"

PATH="$fixture_dir:$PATH" MOCK_MODE=staged \
  scripts/p13-alb-reconciliation-gate.sh \
    --context mock-eks \
    --aws-region ca-central-1 \
    --mode staged \
    --expected-canary-weight 10 \
    --timeout-seconds 1 \
    --poll-seconds 1 \
    --execute >/dev/null

PATH="$fixture_dir:$PATH" MOCK_MODE=promotion \
  scripts/p13-alb-reconciliation-gate.sh \
    --context mock-eks \
    --aws-region ca-central-1 \
    --mode promotion \
    --expected-canary-weight 0 \
    --timeout-seconds 1 \
    --poll-seconds 1 \
    --execute >/dev/null

PATH="$fixture_dir:$PATH" MOCK_MODE=cleanup \
  scripts/p13-alb-reconciliation-gate.sh \
    --context mock-eks \
    --aws-region ca-central-1 \
    --mode cleanup \
    --expected-canary-weight 0 \
    --timeout-seconds 1 \
    --poll-seconds 1 \
    --execute >/dev/null

PATH="$fixture_dir:$PATH" MOCK_MODE=cleanup MOCK_RULE_MODE=cleanup-declared \
  scripts/p13-alb-reconciliation-gate.sh \
    --context mock-eks \
    --aws-region ca-central-1 \
    --mode cleanup \
    --expected-canary-weight 0 \
    --timeout-seconds 1 \
    --poll-seconds 1 \
    --execute >/dev/null

if PATH="$fixture_dir:$PATH" MOCK_MODE=cleanup MOCK_RULE_MODE=cleanup-zero \
  scripts/p13-alb-reconciliation-gate.sh \
    --context mock-eks \
    --aws-region ca-central-1 \
    --mode cleanup \
    --expected-canary-weight 0 \
    --timeout-seconds 1 \
    --poll-seconds 1 \
    --execute >/dev/null 2>&1; then
  printf '%s\n' 'expected a zero-weight stable-only action to fail closed' >&2
  exit 1
fi

if PATH="$fixture_dir:$PATH" MOCK_MODE=staged MOCK_RULE_MODE=cleanup \
  scripts/p13-alb-reconciliation-gate.sh \
    --context mock-eks \
    --aws-region ca-central-1 \
    --mode staged \
    --expected-canary-weight 10 \
    --timeout-seconds 1 \
    --poll-seconds 1 \
    --execute >/dev/null 2>&1; then
  printf '%s\n' 'expected unreconciled ALB rule to fail closed' >&2
  exit 1
fi

# The rollout invokes promotion mode before its drain/cleanup block. A listener
# that remains at the staged 90/10 rule must therefore fail this gate closed.
if PATH="$fixture_dir:$PATH" MOCK_MODE=promotion MOCK_RULE_MODE=staged \
  scripts/p13-alb-reconciliation-gate.sh \
    --context mock-eks \
    --aws-region ca-central-1 \
    --mode promotion \
    --expected-canary-weight 0 \
    --timeout-seconds 1 \
    --poll-seconds 1 \
    --execute >/dev/null 2>&1; then
  printf '%s\n' 'expected lingering 90/10 listener to block promotion cleanup' >&2
  exit 1
fi

# The gate deadline must not race the ELB default. Even with exact 100/0 and a
# healthy replacement, a target group that still reports the default 300-second
# deregistration delay must block promotion cleanup.
if PATH="$fixture_dir:$PATH" MOCK_MODE=promotion MOCK_DEREGISTRATION_DELAY_SECONDS=300 \
  scripts/p13-alb-reconciliation-gate.sh \
    --context mock-eks \
    --aws-region ca-central-1 \
    --mode promotion \
    --expected-canary-weight 0 \
    --timeout-seconds 1 \
    --poll-seconds 1 \
    --execute >/dev/null 2>&1; then
  printf '%s\n' 'expected default 300s deregistration delay to block promotion cleanup' >&2
  exit 1
fi

# M4: a malformed AWS response is a harness error (exit 2), not "not yet reconciled"
# (exit 1) -- and the gate must abort on the first poll instead of waiting out the
# deadline. Give it a deadline generous enough (10s) that only an immediate abort
# could finish this fast; a script that fell back to polling would still be sleeping
# when the wall-clock check below runs.
started_at="$(date +%s)"
gate_status=0
gate_output="$(PATH="$fixture_dir:$PATH" MOCK_MODE=promotion MOCK_ATTRIBUTES_MODE=malformed \
  scripts/p13-alb-reconciliation-gate.sh \
    --context mock-eks \
    --aws-region ca-central-1 \
    --mode promotion \
    --expected-canary-weight 0 \
    --timeout-seconds 10 \
    --poll-seconds 1 \
    --execute 2>&1)" || gate_status=$?
elapsed=$(( $(date +%s) - started_at ))

if ((gate_status != 2)); then
  printf 'expected a malformed AWS response to exit 2 (harness error), got %d\n' "$gate_status" >&2
  exit 1
fi
if ((elapsed >= 5)); then
  printf 'expected the gate to abort on the first poll, not retry for the full 10s deadline (took %ds)\n' \
    "$elapsed" >&2
  exit 1
fi
if ! grep -Fq 'HARNESS ERROR' <<<"$gate_output"; then
  printf 'expected a HARNESS ERROR diagnostic in the gate output, got:\n%s\n' "$gate_output" >&2
  exit 1
fi
if ! grep -Fq 'refusing to keep polling' <<<"$gate_output"; then
  printf 'expected the gate to say it is refusing to keep polling, got:\n%s\n' "$gate_output" >&2
  exit 1
fi

printf '%s\n' 'P13 ALB reconciliation mock tests passed.'
