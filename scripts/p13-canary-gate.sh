#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/p13-canary-gate.sh --context NAME --expected-api-image REF
       --expected-web-image REF [options] [--dry-run|--execute]

Fail-closed P13 canary health/error gate. The default is --dry-run.

Required:
  --context NAME              Explicit kubectl context; never inferred.
  --expected-api-image REF    Exact image expected on deployment/api-canary.
  --expected-web-image REF    Exact image expected on deployment/web-canary.

Options:
  --namespace NAME            Namespace (default: bedoux).
  --weight N                  Expected controller traffic percentage (default: 10).
  --attempts N                Direct canary health samples (default: 20).
  --public-attempts N         Public ALB weighted samples (default: 100).
  --max-errors N              Allowed failed samples (default: 0).
  --aws-region REGION         Required when the active Ingress class is ALB.
  --alb-timeout-seconds N     ALB reconciliation deadline (default: 300).
  --alb-poll-seconds N        ALB reconciliation poll interval (default: 5).
  --dry-run                   Print the bounded checks without contacting a cluster.
  --execute                   Contact the explicit cluster and run the gate.
  --help                      Show this help.

The gate is read-only apart from kubectl exec processes inside the existing canary
web pod. It verifies exact images, one available pod per canary Deployment, the
controller's staged weight, health JSON, a non-empty catalog, and the sampled error
rate. For ALB it also requires the listener rule and both target groups to reconcile,
then correlates bounded public requests with the canary web access log. It creates no
Kubernetes or AWS resource. Exit status 20 is reserved for a sampled HTTP-error
threshold after every prerequisite passed; all other gate blocks use status 1.
EOF
}

context=""
namespace="bedoux"
expected_api_image=""
expected_web_image=""
weight=10
attempts=20
public_attempts=100
max_errors=0
aws_region=""
alb_timeout_seconds=300
alb_poll_seconds=5
execute=false

while (($#)); do
  case "$1" in
    --context|--namespace|--expected-api-image|--expected-web-image|--weight|--attempts|--public-attempts|--max-errors|--aws-region|--alb-timeout-seconds|--alb-poll-seconds)
      if (($# < 2)) || [[ "$2" == --* ]]; then
        usage >&2
        exit 2
      fi
      case "$1" in
        --context) context="$2" ;;
        --namespace) namespace="$2" ;;
        --expected-api-image) expected_api_image="$2" ;;
        --expected-web-image) expected_web_image="$2" ;;
        --weight) weight="$2" ;;
        --attempts) attempts="$2" ;;
        --public-attempts) public_attempts="$2" ;;
        --max-errors) max_errors="$2" ;;
        --aws-region) aws_region="$2" ;;
        --alb-timeout-seconds) alb_timeout_seconds="$2" ;;
        --alb-poll-seconds) alb_poll_seconds="$2" ;;
      esac
      shift
      ;;
    --dry-run)
      execute=false
      ;;
    --execute)
      execute=true
      ;;
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

if [[ -z "$context" || -z "$expected_api_image" || -z "$expected_web_image" ]]; then
  printf '%s\n' 'REFUSING: --context and both expected image references are required.' >&2
  exit 2
fi
for value_name in weight attempts public_attempts max_errors alb_timeout_seconds alb_poll_seconds; do
  value="${!value_name}"
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    printf 'REFUSING: --%s must be a non-negative integer.\n' "${value_name//_/-}" >&2
    exit 2
  fi
done
if ((weight < 1 || weight > 50 || attempts < 1 || public_attempts < 1 || public_attempts > 200 || \
     max_errors >= attempts || \
     alb_timeout_seconds < 1 || alb_timeout_seconds > 600 || \
     alb_poll_seconds < 1 || alb_poll_seconds > 30)); then
  printf '%s\n' 'REFUSING: require weight 1..50, attempts >= 1, public-attempts 1..200, max-errors < attempts, ALB timeout 1..600s, and poll 1..30s.' >&2
  exit 2
fi

if [[ "$execute" == false ]]; then
  printf 'DRY RUN: context=<explicit> namespace=%s weight=%d attempts=%d public_attempts=%d max_errors=%d\n' \
    "$namespace" "$weight" "$attempts" "$public_attempts" "$max_errors"
  printf '%s\n' 'DRY RUN: verify exact canary images, one available pod per Deployment, and controller weight.'
  printf '%s\n' 'DRY RUN: for ALB, require exact listener weights, 30s deregistration, and healthy targets.'
  printf '%s\n' 'DRY RUN: for ALB, send bounded public probes and require a matching web-canary access log.'
  printf '%s\n' 'DRY RUN: sample /api/health through web-canary, then require a non-empty canary catalog.'
  exit 0
fi

command -v kubectl >/dev/null
command -v python >/dev/null

kubectl_args=(--context "$context" --namespace "$namespace")
controller_kind=""

assert_deployment() {
  local deployment="$1"
  local expected_image="$2"
  local desired available actual_image pod_count

  desired="$(kubectl "${kubectl_args[@]}" get deployment "$deployment" \
    --output jsonpath='{.spec.replicas}')"
  available="$(kubectl "${kubectl_args[@]}" get deployment "$deployment" \
    --output jsonpath='{.status.availableReplicas}')"
  actual_image="$(kubectl "${kubectl_args[@]}" get deployment "$deployment" \
    --output jsonpath='{.spec.template.spec.containers[0].image}')"
  pod_count="$(kubectl "${kubectl_args[@]}" get pods --selector "app=$deployment" \
    --field-selector status.phase=Running --output name | wc -l)"

  if [[ "$desired" != 1 || "$available" != 1 || "$pod_count" != 1 ]]; then
    printf 'BLOCK: deployment/%s must have exactly one desired, available, Running pod.\n' \
      "$deployment" >&2
    exit 1
  fi
  if [[ "$actual_image" != "$expected_image" ]]; then
    printf 'BLOCK: deployment/%s image does not match the verified candidate.\n' \
      "$deployment" >&2
    exit 1
  fi
}

assert_weight() {
  local action api_weight web_weight
  if kubectl "${kubectl_args[@]}" get ingress bedoux >/dev/null 2>&1; then
    controller_kind="alb"
    action="$(kubectl "${kubectl_args[@]}" get ingress bedoux \
      --output jsonpath='{.metadata.annotations.alb\.ingress\.kubernetes\.io/actions\.web}')"
    python scripts/lib/gate_checks.py alb-weight-matches --weight "$weight" <<<"$action"
    return
  fi

  controller_kind="nginx"

  api_weight="$(kubectl "${kubectl_args[@]}" get ingress bedoux-api-canary \
    --output jsonpath='{.metadata.annotations.nginx\.ingress\.kubernetes\.io/canary-weight}')"
  web_weight="$(kubectl "${kubectl_args[@]}" get ingress bedoux-web-canary \
    --output jsonpath='{.metadata.annotations.nginx\.ingress\.kubernetes\.io/canary-weight}')"
  if [[ "$api_weight" != "$weight" || "$web_weight" != "$weight" ]]; then
    printf 'BLOCK: ingress-nginx canary weights are not both %s.\n' "$weight" >&2
    exit 1
  fi
}

assert_deployment api-canary "$expected_api_image"
assert_deployment web-canary "$expected_web_image"
assert_weight

count_probe_statuses() {
  local probe_key="$1"
  python scripts/lib/gate_checks.py count-probe-statuses --marker "$probe_key"
}

public_errors=0
public_canary_hits=0
public_canary_http_errors=0

if [[ "$controller_kind" == "alb" ]]; then
  if [[ -z "$aws_region" ]]; then
    printf '%s\n' 'BLOCK: --aws-region is required before an ALB canary can be promoted.' >&2
    exit 1
  fi
  scripts/p13-alb-reconciliation-gate.sh \
    --context "$context" \
    --namespace "$namespace" \
    --aws-region "$aws_region" \
    --mode staged \
    --expected-canary-weight "$weight" \
    --timeout-seconds "$alb_timeout_seconds" \
    --poll-seconds "$alb_poll_seconds" \
    --execute

  command -v curl >/dev/null
  alb_hostname="$(kubectl "${kubectl_args[@]}" get ingress bedoux \
    --output jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
  if [[ ! "$alb_hostname" =~ ^[A-Za-z0-9.-]+\.elb\.amazonaws\.com$ ]]; then
    printf '%s\n' 'BLOCK: active ALB hostname is unavailable for the public weighted sample.' >&2
    exit 1
  fi
  printf -v probe_prefix 'p13-canary-%05d-%05d' "$RANDOM" "$RANDOM"
  public_errors=0
  for ((attempt = 1; attempt <= public_attempts; attempt++)); do
    if public_health_json="$(curl --fail --silent \
      --connect-timeout 2 --max-time 5 \
      "http://$alb_hostname/api/health?bedoux_canary_probe=$probe_prefix-$attempt")" && \
      python scripts/lib/gate_checks.py health-status-ok <<<"$public_health_json"; then
      :
    else
      public_errors=$((public_errors + 1))
    fi
  done
  canary_logs="$(kubectl "${kubectl_args[@]}" logs deployment/web-canary --since=5m)"
  read -r public_canary_hits public_canary_http_errors < <(
    count_probe_statuses "bedoux_canary_probe=$probe_prefix-" <<<"$canary_logs"
  )
  printf 'PUBLIC_CANARY_GATE attempts=%d errors=%d canary_log_hits=%d canary_http_errors=%d\n' \
    "$public_attempts" "$public_errors" "$public_canary_hits" "$public_canary_http_errors"
  if ((public_canary_hits < 1)); then
    printf '%s\n' 'BLOCK: public 90/10 sample did not reach web-canary.' >&2
    exit 1
  fi
fi

errors=0
printf -v direct_probe_prefix 'p13-direct-%05d-%05d' "$RANDOM" "$RANDOM"
for ((attempt = 1; attempt <= attempts; attempt++)); do
  if health_json="$(kubectl "${kubectl_args[@]}" exec deployment/web-canary -- \
    wget -qO- -T 10 \
      "http://127.0.0.1:8080/api/health?bedoux_direct_canary_probe=$direct_probe_prefix-$attempt")" && \
    python scripts/lib/gate_checks.py health-status-ok <<<"$health_json"; then
    :
  else
    errors=$((errors + 1))
  fi
done

direct_logs="$(kubectl "${kubectl_args[@]}" logs deployment/web-canary --since=5m)"
read -r direct_log_hits direct_http_errors < <(
  count_probe_statuses "bedoux_direct_canary_probe=$direct_probe_prefix-" <<<"$direct_logs"
)
error_rate="$(python scripts/lib/gate_checks.py error-rate "$errors" "$attempts")"
printf 'CANARY_GATE attempts=%d errors=%d error_rate=%s log_hits=%d http_errors=%d\n' \
  "$attempts" "$errors" "$error_rate" "$direct_log_hits" "$direct_http_errors"
if ((direct_log_hits != attempts)); then
  printf 'BLOCK: direct sample produced %d requests but only %d correlated access-log entries.\n' \
    "$attempts" "$direct_log_hits" >&2
  exit 1
fi
if ((errors > max_errors)); then
  if ((direct_http_errors == errors && direct_http_errors > max_errors)); then
    if [[ "$controller_kind" == "alb" ]] && \
       ((public_errors <= max_errors || public_canary_http_errors <= max_errors)); then
      printf '%s\n' \
        'BLOCK: direct HTTP errors were observed, but the public ALB sample did not prove a correlated canary HTTP error.' >&2
      exit 1
    fi
    printf 'CANARY_GATE_RESULT prerequisites=passed reason=http-error-threshold public_http_errors=%d direct_http_errors=%d\n' \
      "$public_canary_http_errors" "$direct_http_errors"
    exit 20
  fi
  printf 'BLOCK: canary sample failures were not fully attributable to HTTP error responses (%d failures, %d HTTP errors).\n' \
    "$errors" "$direct_http_errors" >&2
  exit 1
fi
if ((public_errors > max_errors || public_canary_http_errors > max_errors)); then
  printf '%s\n' 'BLOCK: public ALB sample failed without a matching direct canary HTTP-error threshold.' >&2
  exit 1
fi

catalog_json="$(kubectl "${kubectl_args[@]}" exec deployment/web-canary -- \
  wget -qO- -T 10 'http://127.0.0.1:8080/api/products?limit=1')"
python scripts/lib/gate_checks.py catalog-nonempty <<<"$catalog_json"

printf '%s\n' 'PASS: exact canary images, reconciled staged weight, health/error sample, and catalog gate passed.'
