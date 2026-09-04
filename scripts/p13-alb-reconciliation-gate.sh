#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/p13-alb-reconciliation-gate.sh --context NAME --aws-region REGION
       --mode MODE --expected-canary-weight N [options] [--dry-run|--execute]

Fail-closed, read-only proof that an AWS ALB has reconciled the P13 forward action.
The default is --dry-run. It never prints ALB or target-group ARNs.

Required:
  --context NAME                  Explicit kubectl context.
  --aws-region REGION             Explicit AWS region.
  --mode MODE                     staged, promotion, or cleanup.
  --expected-canary-weight N      1..50 for staged; 0 for promotion/cleanup.

Options:
  --namespace NAME                Namespace (default: bedoux).
  --ingress NAME                  ALB Ingress (default: bedoux).
  --stable-service NAME           Stable web Service (default: web).
  --canary-service NAME           Canary web Service (default: web-canary).
  --timeout-seconds N             Reconciliation deadline (default: 300).
  --poll-seconds N                Poll interval (default: 5).
  --dry-run                       Print bounded checks without contacting AWS/Kubernetes.
  --execute                       Perform read-only Kubernetes and ELBv2 checks.
  --help                          Show this help.

Staged mode requires both TargetGroupBindings, exact non-zero weights, and both groups
fully healthy. Every mode also requires the controller-applied 30-second target-group
deregistration delay. Promotion mode keeps both bindings, requires exact 100/0 weights,
and requires the stable group fully healthy before the drain clock may start. Cleanup
mode requires no canary binding, a stable-only 100% action, and a fully healthy stable
group. AWS may normalize that sole target group's relative weight to any positive value
(observed as 1); with no second target group, it still receives 100% of forwarded traffic.
EOF
}

context=""
aws_region=""
namespace="bedoux"
ingress="bedoux"
stable_service="web"
canary_service="web-canary"
expected_canary_weight=""
mode=""
timeout_seconds=300
poll_seconds=5
execute=false

while (($#)); do
  case "$1" in
    --context|--aws-region|--namespace|--ingress|--stable-service|--canary-service|--mode|--expected-canary-weight|--timeout-seconds|--poll-seconds)
      if (($# < 2)) || [[ "$2" == --* ]]; then
        usage >&2
        exit 2
      fi
      case "$1" in
        --context) context="$2" ;;
        --aws-region) aws_region="$2" ;;
        --namespace) namespace="$2" ;;
        --ingress) ingress="$2" ;;
        --stable-service) stable_service="$2" ;;
        --canary-service) canary_service="$2" ;;
        --mode) mode="$2" ;;
        --expected-canary-weight) expected_canary_weight="$2" ;;
        --timeout-seconds) timeout_seconds="$2" ;;
        --poll-seconds) poll_seconds="$2" ;;
      esac
      shift
      ;;
    --dry-run) execute=false ;;
    --execute) execute=true ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ -z "$context" || -z "$aws_region" || -z "$mode" || -z "$expected_canary_weight" ]]; then
  printf '%s\n' 'REFUSING: --context, --aws-region, --mode, and --expected-canary-weight are required.' >&2
  exit 2
fi
for value_name in expected_canary_weight timeout_seconds poll_seconds; do
  value="${!value_name}"
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    printf 'REFUSING: --%s must be a non-negative integer.\n' "${value_name//_/-}" >&2
    exit 2
  fi
done
if ((expected_canary_weight > 50 || timeout_seconds < 1 || timeout_seconds > 600 || \
     poll_seconds < 1 || poll_seconds > 30)); then
  printf '%s\n' 'REFUSING: weight must be 0..50, timeout 1..600s, and poll 1..30s.' >&2
  exit 2
fi
case "$mode" in
  staged)
    if ((expected_canary_weight < 1)); then
      printf '%s\n' 'REFUSING: staged mode requires a canary weight from 1..50.' >&2
      exit 2
    fi
    ;;
  promotion|cleanup)
    if ((expected_canary_weight != 0)); then
      printf 'REFUSING: %s mode requires canary weight 0.\n' "$mode" >&2
      exit 2
    fi
    ;;
  *)
    printf '%s\n' 'REFUSING: --mode must be staged, promotion, or cleanup.' >&2
    exit 2
    ;;
esac
if [[ ! "$aws_region" =~ ^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$ ]]; then
  printf '%s\n' 'REFUSING: --aws-region is not a valid explicit AWS region.' >&2
  exit 2
fi

if [[ "$execute" == false ]]; then
  printf 'DRY RUN: context=<explicit> region=%s namespace=%s mode=%s canary_weight=%d timeout=%ds poll=%ds\n' \
    "$aws_region" "$namespace" "$mode" "$expected_canary_weight" "$timeout_seconds" "$poll_seconds"
  printf '%s\n' 'DRY RUN: map Services to TargetGroupBindings without printing ARNs.'
  printf '%s\n' 'DRY RUN: require active ALB, exact reconciled listener weights, and all targets healthy.'
  printf '%s\n' 'DRY RUN: require every active target group to report deregistration_delay.timeout_seconds=30.'
  exit 0
fi

command -v aws >/dev/null
command -v kubectl >/dev/null
command -v python >/dev/null

kubectl_args=(--context "$context" --namespace "$namespace")
aws_args=(--region "$aws_region" --no-cli-pager)

# M4: scripts/lib/gate_checks.py replaces this file's inline embedded-Python assertions. Every
# check returns 0 (true), 1 (not yet true -- expected while polling, keep trying), or 2
# (the check could not be evaluated -- malformed AWS/Kubernetes response or a violated
# invariant, diagnosed on stderr). verify_reconciliation_once propagates that same
# three-way result so the polling loop below can stop immediately on a 2 instead of
# retrying a broken assertion for the full timeout.
gate_check() {
  python scripts/lib/gate_checks.py "$@"
}

verify_reconciliation_once() {
  local ingress_class alb_hostname tgb_json load_balancers_json alb_arn_value
  local listeners_json rules_json stable_attributes_json canary_attributes_json
  local stable_health_json canary_health_json
  local stable_target_group_arn canary_target_group_arn listener_arn
  local target_group_output status
  local -a target_group_arns=() listener_arns=()

  ingress_class="$(kubectl "${kubectl_args[@]}" get ingress "$ingress" \
    --output jsonpath='{.spec.ingressClassName}' 2>/dev/null)" || return 1
  [[ "$ingress_class" == "alb" ]] || return 1
  alb_hostname="$(kubectl "${kubectl_args[@]}" get ingress "$ingress" \
    --output jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)" || return 1
  [[ "$alb_hostname" =~ ^[A-Za-z0-9.-]+\.elb\.amazonaws\.com$ ]] || return 1

  tgb_json="$(kubectl "${kubectl_args[@]}" get targetgroupbindings.elbv2.k8s.aws \
    --output json 2>/dev/null)" || return 1
  status=0
  target_group_output="$(gate_check target-group-arns \
    --stable-service "$stable_service" --canary-service "$canary_service" --mode "$mode" \
    <<<"$tgb_json")" || status=$?
  if ((status != 0)); then
    ((status == 2)) && return 2
    return 1
  fi
  mapfile -t target_group_arns <<<"$target_group_output"
  if [[ "$mode" != "cleanup" ]]; then
    canary_target_group_arn="${target_group_arns[1]}"
  else
    canary_target_group_arn=""
  fi
  stable_target_group_arn="${target_group_arns[0]}"

  load_balancers_json="$(aws elbv2 describe-load-balancers "${aws_args[@]}" \
    --output json 2>/dev/null)" || return 1
  status=0
  alb_arn_value="$(gate_check alb-arn --hostname "$alb_hostname" <<<"$load_balancers_json")" || status=$?
  if ((status != 0)); then
    ((status == 2)) && return 2
    return 1
  fi

  listeners_json="$(aws elbv2 describe-listeners "${aws_args[@]}" \
    --load-balancer-arn "$alb_arn_value" --output json 2>/dev/null)" || return 1
  status=0
  target_group_output="$(gate_check listener-arns <<<"$listeners_json")" || status=$?
  if ((status != 0)); then
    ((status == 2)) && return 2
    return 1
  fi
  mapfile -t listener_arns <<<"$target_group_output"
  ((${#listener_arns[@]} >= 1)) || return 1

  local matching_rule=false
  for listener_arn in "${listener_arns[@]}"; do
    rules_json="$(aws elbv2 describe-rules "${aws_args[@]}" \
      --listener-arn "$listener_arn" --output json 2>/dev/null)" || return 1
    status=0
    gate_check rule-weight-matches \
      --stable "$stable_target_group_arn" --canary "$canary_target_group_arn" \
      --weight "$expected_canary_weight" --mode "$mode" <<<"$rules_json" || status=$?
    if ((status == 0)); then
      matching_rule=true
      break
    fi
    ((status == 2)) && return 2
  done
  [[ "$matching_rule" == true ]] || return 1

  stable_attributes_json="$(aws elbv2 describe-target-group-attributes "${aws_args[@]}" \
    --target-group-arn "$stable_target_group_arn" --output json 2>/dev/null)" || return 1
  status=0
  gate_check deregistration-delay --expected-seconds 30 <<<"$stable_attributes_json" || status=$?
  if ((status != 0)); then
    ((status == 2)) && return 2
    return 1
  fi

  if [[ "$mode" != "cleanup" ]]; then
    canary_attributes_json="$(aws elbv2 describe-target-group-attributes "${aws_args[@]}" \
      --target-group-arn "$canary_target_group_arn" --output json 2>/dev/null)" || return 1
    status=0
    gate_check deregistration-delay --expected-seconds 30 <<<"$canary_attributes_json" || status=$?
    if ((status != 0)); then
      ((status == 2)) && return 2
      return 1
    fi
  fi

  stable_health_json="$(aws elbv2 describe-target-health "${aws_args[@]}" \
    --target-group-arn "$stable_target_group_arn" --output json 2>/dev/null)" || return 1
  status=0
  gate_check target-health <<<"$stable_health_json" || status=$?
  if ((status != 0)); then
    ((status == 2)) && return 2
    return 1
  fi

  if [[ "$mode" == "staged" ]]; then
    canary_health_json="$(aws elbv2 describe-target-health "${aws_args[@]}" \
      --target-group-arn "$canary_target_group_arn" --output json 2>/dev/null)" || return 1
    status=0
    gate_check target-health <<<"$canary_health_json" || status=$?
    if ((status != 0)); then
      ((status == 2)) && return 2
      return 1
    fi
  fi
}

deadline=$((SECONDS + timeout_seconds))
poll=0
while ((SECONDS <= deadline)); do
  poll=$((poll + 1))
  # Not `if verify_reconciliation_once; then ... fi` -- when the condition of an `if`
  # with no `else` is false, the *if statement's own* exit status is 0 per POSIX, which
  # would silently discard the distinction between "not yet" (1) and "harness error" (2)
  # this whole rewrite exists to preserve. `&&`/`||` instead, so $? always reflects
  # verify_reconciliation_once's real return code.
  gate_status=0
  verify_reconciliation_once || gate_status=$?
  if ((gate_status == 0)); then
    if [[ "$mode" == "staged" ]]; then
      printf 'ALB_RECONCILIATION_GATE mode=staged weight=%d target_groups=2 deregistration_delay=30 healthy=true\n' \
        "$expected_canary_weight"
    elif [[ "$mode" == "promotion" ]]; then
      printf '%s\n' 'ALB_RECONCILIATION_GATE mode=promotion weight=100/0 target_groups=2 deregistration_delay=30 stable_healthy=true'
    else
      printf '%s\n' 'ALB_RECONCILIATION_GATE mode=cleanup weight=100 target_groups=1 deregistration_delay=30 healthy=true'
    fi
    printf '%s\n' 'PASS: ALB listener action, deregistration delay, and target health are fully reconciled.'
    exit 0
  fi
  if ((gate_status == 2)); then
    printf 'BLOCK: a reconciliation check could not be evaluated (see the HARNESS ERROR diagnostic above); refusing to keep polling.\n' >&2
    exit 2
  fi
  if ((SECONDS + poll_seconds > deadline)); then
    break
  fi
  printf 'ALB_GATE_WAIT poll=%d state=not-yet-reconciled\n' "$poll"
  sleep "$poll_seconds"
done

printf 'BLOCK: ALB did not reconcile the expected action and healthy targets within %d seconds.\n' \
  "$timeout_seconds" >&2
exit 1
