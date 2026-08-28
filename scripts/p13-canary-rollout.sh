#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/p13-canary-rollout.sh --context NAME --stable-api-image REF
       --stable-web-image REF --candidate-api-image REF --candidate-web-image REF
       [options] [--dry-run|--execute]

Stage, gate, promote, and clean up one P13 canary inside the existing Helm release.
The default is --dry-run. Image references may be repository@sha256:digest (required
by CI) or repository:tag (for a local kind proof).

Required:
  --context NAME              Explicit kubectl/Helm context.
  --stable-api-image REF      Exact image currently running on deployment/api.
  --stable-web-image REF      Exact image currently running on deployment/web.
  --candidate-api-image REF   Verified candidate API image.
  --candidate-web-image REF   Verified candidate web image.

Options:
  --namespace NAME            Namespace (default: bedoux).
  --release NAME              Helm release (default: bedoux).
  --chart PATH                Chart path (default: charts/bedoux).
  --values PATH               Repeatable Helm values file.
  --helm-set KEY=VALUE        Repeatable non-secret Helm --set override.
  --weight N                  Staged canary percentage (default: 10).
  --attempts N                Gate request count (default: 20).
  --max-errors N              Gate error allowance (default: 0).
  --aws-region REGION         Required when the active Ingress class is ALB.
  --alb-timeout-seconds N     ALB stage/cleanup reconciliation deadline (default: 300).
  --alb-poll-seconds N        ALB reconciliation poll interval (default: 5).
  --drain-seconds N           100/0 hold before canary removal (default: 45).
  --timeout DURATION          Helm timeout (default: 10m).
  --dry-run                   Print phases without contacting a cluster.
  --execute                   Perform the rollout against the explicit context.
  --help                      Show this help.

Before promotion, every failure reapplies the captured stable images with canary
disabled. Each Helm mutation uses --atomic. The final 100/0 hold lets controllers
reconcile away from canary targets before their bounded removal.
EOF
}

context=""
namespace="bedoux"
release="bedoux"
chart="charts/bedoux"
stable_api_image=""
stable_web_image=""
candidate_api_image=""
candidate_web_image=""
weight=10
attempts=20
max_errors=0
aws_region=""
alb_timeout_seconds=300
alb_poll_seconds=5
drain_seconds=45
timeout="10m"
execute=false
declare -a values_files=()
declare -a helm_sets=()

while (($#)); do
  case "$1" in
    --context|--namespace|--release|--chart|--stable-api-image|--stable-web-image|--candidate-api-image|--candidate-web-image|--weight|--attempts|--max-errors|--aws-region|--alb-timeout-seconds|--alb-poll-seconds|--drain-seconds|--timeout|--values|--helm-set)
      if (($# < 2)) || [[ "$2" == --* ]]; then
        usage >&2
        exit 2
      fi
      case "$1" in
        --context) context="$2" ;;
        --namespace) namespace="$2" ;;
        --release) release="$2" ;;
        --chart) chart="$2" ;;
        --stable-api-image) stable_api_image="$2" ;;
        --stable-web-image) stable_web_image="$2" ;;
        --candidate-api-image) candidate_api_image="$2" ;;
        --candidate-web-image) candidate_web_image="$2" ;;
        --weight) weight="$2" ;;
        --attempts) attempts="$2" ;;
        --max-errors) max_errors="$2" ;;
        --aws-region) aws_region="$2" ;;
        --alb-timeout-seconds) alb_timeout_seconds="$2" ;;
        --alb-poll-seconds) alb_poll_seconds="$2" ;;
        --drain-seconds) drain_seconds="$2" ;;
        --timeout) timeout="$2" ;;
        --values) values_files+=("$2") ;;
        --helm-set) helm_sets+=("$2") ;;
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

if [[ -z "$context" || -z "$stable_api_image" || -z "$stable_web_image" || \
      -z "$candidate_api_image" || -z "$candidate_web_image" ]]; then
  printf '%s\n' 'REFUSING: explicit context and all four image references are required.' >&2
  exit 2
fi
for value_name in weight attempts max_errors alb_timeout_seconds alb_poll_seconds drain_seconds; do
  value="${!value_name}"
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    printf 'REFUSING: --%s must be a non-negative integer.\n' "${value_name//_/-}" >&2
    exit 2
  fi
done
if ((weight < 1 || weight > 50 || attempts < 1 || max_errors >= attempts || \
     alb_timeout_seconds < 1 || alb_timeout_seconds > 600 || \
     alb_poll_seconds < 1 || alb_poll_seconds > 30)); then
  printf '%s\n' 'REFUSING: require weight 1..50, attempts >= 1, max-errors < attempts, ALB timeout 1..600s, and poll 1..30s.' >&2
  exit 2
fi
if [[ "$stable_api_image" == "$candidate_api_image" || \
      "$stable_web_image" == "$candidate_web_image" ]]; then
  printf '%s\n' 'REFUSING: both candidate images must differ from the captured stable images.' >&2
  exit 2
fi

for file in "${values_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    printf 'REFUSING: values file does not exist: %s\n' "$file" >&2
    exit 2
  fi
done

if [[ "$execute" == false ]]; then
  printf 'DRY RUN: context=<explicit> namespace=%s release=%s weight=%d attempts=%d max_errors=%d\n' \
    "$namespace" "$release" "$weight" "$attempts" "$max_errors"
  printf '%s\n' 'DRY RUN: assert the running stable images exactly match the captured baseline.'
  printf '%s\n' 'DRY RUN: for ALB, normalize and reconcile the stable-only action before staging.'
  printf '%s\n' 'DRY RUN: stage weighted traffic; for ALB, wait for exact listener/target-health reconciliation.'
  printf 'DRY RUN: promote candidate at 100/0, hold %d seconds, then remove canary resources.\n' \
    "$drain_seconds"
  printf '%s\n' 'DRY RUN: verify canary Deployments, Services, Ingresses, and weighted targets are removed.'
  printf '%s\n' 'DRY RUN: any pre-promotion failure reapplies the captured stable images with canary disabled.'
  exit 0
fi

command -v helm >/dev/null
command -v kubectl >/dev/null

append_image_values() {
  local target_name="$1"
  local prefix="$2"
  local reference="$3"
  local repository tag digest
  local -n target="$target_name"

  if [[ "$reference" == *@sha256:* ]]; then
    repository="${reference%@sha256:*}"
    digest="sha256:${reference##*@sha256:}"
    if [[ ! "$digest" =~ ^sha256:[0-9a-f]{64}$ || -z "$repository" ]]; then
      printf 'REFUSING: invalid digest image reference for %s.\n' "$prefix" >&2
      exit 2
    fi
    target+=(--set-string "$prefix.repository=$repository")
    target+=(--set-string "$prefix.tag=")
    target+=(--set-string "$prefix.digest=$digest")
    return
  fi

  repository="${reference%:*}"
  tag="${reference##*:}"
  if [[ -z "$repository" || -z "$tag" || "$repository" == "$reference" ]]; then
    printf 'REFUSING: invalid tagged image reference for %s.\n' "$prefix" >&2
    exit 2
  fi
  target+=(--set-string "$prefix.repository=$repository")
  target+=(--set-string "$prefix.tag=$tag")
  target+=(--set-string "$prefix.digest=")
}

helm_base=(upgrade "$release" "$chart" --install --namespace "$namespace" \
  --kube-context "$context" --reset-values --wait --wait-for-jobs --timeout "$timeout" --atomic)
for file in "${values_files[@]}"; do
  helm_base+=(-f "$file")
done
for setting in "${helm_sets[@]}"; do
  helm_base+=(--set "$setting")
done

stable_values=()
append_image_values stable_values api.image "$stable_api_image"
append_image_values stable_values web.image "$stable_web_image"

candidate_values=()
append_image_values candidate_values api.image "$candidate_api_image"
append_image_values candidate_values web.image "$candidate_web_image"

canary_candidate_values=()
append_image_values canary_candidate_values canary.api.image "$candidate_api_image"
append_image_values canary_candidate_values canary.web.image "$candidate_web_image"

kubectl_args=(--context "$context" --namespace "$namespace")
helm status "$release" --namespace "$namespace" --kube-context "$context" >/dev/null
actual_stable_api="$(kubectl "${kubectl_args[@]}" get deployment api \
  --output jsonpath='{.spec.template.spec.containers[0].image}')"
actual_stable_web="$(kubectl "${kubectl_args[@]}" get deployment web \
  --output jsonpath='{.spec.template.spec.containers[0].image}')"
if [[ "$actual_stable_api" != "$stable_api_image" || "$actual_stable_web" != "$stable_web_image" ]]; then
  printf '%s\n' 'REFUSING: captured stable images do not match the running Deployments.' >&2
  exit 1
fi

assert_absent() {
  local resource="$1"
  local name="$2"
  local found
  if ! found="$(kubectl "${kubectl_args[@]}" get "$resource" "$name" \
    --ignore-not-found --output name)"; then
    printf 'BLOCK: could not verify cleanup state for %s/%s.\n' "$resource" "$name" >&2
    return 1
  fi
  if [[ -n "$found" ]]; then
    printf 'BLOCK: %s/%s remains after canary cleanup.\n' "$resource" "$name" >&2
    return 1
  fi
}

get_service_target_group_arn() {
  local service="$1"
  local bindings_json
  bindings_json="$(kubectl "${kubectl_args[@]}" get targetgroupbindings.elbv2.k8s.aws \
    --output json)" || return 1
  SERVICE_NAME="$service" python -c '
import json, os, sys
matches = [item["spec"]["targetGroupARN"]
           for item in json.load(sys.stdin).get("items", [])
           if item.get("spec", {}).get("serviceRef", {}).get("name") == os.environ["SERVICE_NAME"]]
if len(matches) != 1:
    raise SystemExit(1)
print(matches[0])
' <<<"$bindings_json"
}

verify_cleanup() {
  local action

  assert_absent deployment api-canary
  assert_absent deployment web-canary
  assert_absent service api-canary
  assert_absent service web-canary
  assert_absent configmap web-canary-config
  assert_absent ingress bedoux-api-canary
  assert_absent ingress bedoux-web-canary

  if kubectl "${kubectl_args[@]}" get ingress bedoux >/dev/null 2>&1; then
    action="$(kubectl "${kubectl_args[@]}" get ingress bedoux \
      --output jsonpath='{.metadata.annotations.alb\.ingress\.kubernetes\.io/actions\.web}')"
    python -c '
import json, sys
action = json.load(sys.stdin)
groups = {item["serviceName"]: item["weight"]
          for item in action["forwardConfig"]["targetGroups"]}
assert groups == {"web": 100}, groups
' <<<"$action"
    if [[ -z "$aws_region" ]]; then
      printf '%s\n' 'BLOCK: --aws-region is required to verify ALB cleanup reconciliation.' >&2
      return 1
    fi
    scripts/p13-alb-reconciliation-gate.sh \
      --context "$context" \
      --namespace "$namespace" \
      --aws-region "$aws_region" \
      --expected-canary-weight 0 \
      --timeout-seconds "$alb_timeout_seconds" \
      --poll-seconds "$alb_poll_seconds" \
      --execute
    return
  fi

  kubectl "${kubectl_args[@]}" get ingress bedoux-api >/dev/null
  kubectl "${kubectl_args[@]}" get ingress bedoux-web >/dev/null
}

abort_to_stable() {
  printf '%s\n' 'ABORT: removing canary and restoring the captured stable images.' >&2
  helm "${helm_base[@]}" "${stable_values[@]}" \
    --set canary.enabled=false --set migration.enabled=false
  kubectl "${kubectl_args[@]}" rollout status deployment/api --timeout=5m
  kubectl "${kubectl_args[@]}" rollout status deployment/web --timeout=5m
  verify_cleanup
}

if kubectl "${kubectl_args[@]}" get ingress bedoux >/dev/null 2>&1; then
  stable_target_group_before=""
  stable_target_group_after=""
  if [[ -z "$aws_region" ]]; then
    printf '%s\n' 'REFUSING: --aws-region is required for an ALB rollout.' >&2
    exit 1
  fi
  if ! stable_target_group_before="$(get_service_target_group_arn web)"; then
    printf '%s\n' 'REFUSING: baseline must have exactly one controller-owned target group for Service/web.' >&2
    exit 1
  fi
  printf '%s\n' 'PREPARE: reconciling the stable release through the persistent ALB action backend.'
  helm "${helm_base[@]}" "${stable_values[@]}" \
    --set canary.enabled=false --set migration.enabled=false
  kubectl "${kubectl_args[@]}" rollout status deployment/api --timeout=5m
  kubectl "${kubectl_args[@]}" rollout status deployment/web --timeout=5m
  verify_cleanup
  if ! stable_target_group_after="$(get_service_target_group_arn web)"; then
    printf '%s\n' 'BLOCK: stable target-group identity could not be verified after action normalization.' >&2
    exit 1
  fi
  if [[ "$stable_target_group_after" != "$stable_target_group_before" ]]; then
    printf '%s\n' 'BLOCK: action normalization replaced the stable target group.' >&2
    exit 1
  fi
  unset stable_target_group_before stable_target_group_after
  printf '%s\n' 'PASS: stable-only ALB action is reconciled before canary staging.'
fi

stage_succeeded=false
printf 'STAGE: routing %d%% to the verified candidate.\n' "$weight"
if helm "${helm_base[@]}" "${stable_values[@]}" "${canary_candidate_values[@]}" \
  --set canary.enabled=true --set "canary.weight=$weight"; then
  stage_succeeded=true
else
  printf '%s\n' 'BLOCK: atomic canary stage failed; stable release remains authoritative.' >&2
  exit 1
fi

gate_args=(
  --context "$context"
  --namespace "$namespace"
  --expected-api-image "$candidate_api_image"
  --expected-web-image "$candidate_web_image"
  --weight "$weight"
  --attempts "$attempts"
  --max-errors "$max_errors"
  --alb-timeout-seconds "$alb_timeout_seconds"
  --alb-poll-seconds "$alb_poll_seconds"
)
if [[ -n "$aws_region" ]]; then
  gate_args+=(--aws-region "$aws_region")
fi

if ! kubectl "${kubectl_args[@]}" rollout status deployment/api-canary --timeout=5m || \
   ! kubectl "${kubectl_args[@]}" rollout status deployment/web-canary --timeout=5m || \
   ! scripts/p13-canary-gate.sh "${gate_args[@]}" --execute; then
  if [[ "$stage_succeeded" == true ]]; then
    abort_to_stable
  fi
  exit 1
fi

printf '%s\n' 'PROMOTE: gate passed; changing the split to stable candidate 100%, canary 0%.'
if ! helm "${helm_base[@]}" "${candidate_values[@]}" "${canary_candidate_values[@]}" \
  --set canary.enabled=true --set canary.weight=0; then
  abort_to_stable
  exit 1
fi
if ! kubectl "${kubectl_args[@]}" rollout status deployment/api --timeout=5m || \
   ! kubectl "${kubectl_args[@]}" rollout status deployment/web --timeout=5m; then
  abort_to_stable
  exit 1
fi

printf 'DRAIN: holding the 100/0 split for %d seconds before canary removal.\n' "$drain_seconds"
sleep "$drain_seconds"

printf '%s\n' 'CLEANUP: removing zero-weight canary resources.'
helm "${helm_base[@]}" "${candidate_values[@]}" \
  --set canary.enabled=false --set migration.enabled=false
kubectl "${kubectl_args[@]}" rollout status deployment/api --timeout=5m
kubectl "${kubectl_args[@]}" rollout status deployment/web --timeout=5m

final_api_image="$(kubectl "${kubectl_args[@]}" get deployment api \
  --output jsonpath='{.spec.template.spec.containers[0].image}')"
final_web_image="$(kubectl "${kubectl_args[@]}" get deployment web \
  --output jsonpath='{.spec.template.spec.containers[0].image}')"
if [[ "$final_api_image" != "$candidate_api_image" || "$final_web_image" != "$candidate_web_image" ]]; then
  printf '%s\n' 'BLOCK: final stable Deployments do not contain the promoted candidate images.' >&2
  exit 1
fi
verify_cleanup

printf '%s\n' 'PASS: canary staged, reconciled, gated, promoted to 100%, and fully cleaned up.'
