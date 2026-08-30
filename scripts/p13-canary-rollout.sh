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
  --public-attempts N         Public ALB weighted samples (default: 100).
  --max-errors N              Gate error allowance (default: 0).
  --aws-region REGION         Required when the active Ingress class is ALB.
  --alb-timeout-seconds N     ALB reconciliation deadline per state (default: 300).
  --alb-poll-seconds N        ALB reconciliation poll interval (default: 5).
  --drain-seconds N           100/0 hold before canary removal (default: 45).
  --regression-mode MODE      Expected gate-block drill: none or http-error
                              (default: none).
  --timeout DURATION          Helm timeout (default: 10m).
  --dry-run                   Print phases without contacting a cluster.
  --execute                   Perform the rollout against the explicit context.
  --help                      Show this help.

Before promotion, every failure restores the captured stable images through a
reconciled 100/0 hold before canary removal. Each Helm mutation uses --atomic. On
ALB, the drain hold starts only after the listener is exactly 100/0 and stable pods
and targets are confirmed healthy. Every ALB Helm mutation pins the target-group
deregistration delay to the project-proven 30-second bound, and each reconciliation
gate verifies the controller-applied AWS attribute before proceeding.
In http-error regression mode, Ready canary pods deliberately return API errors.
The command succeeds only when the health gate blocks promotion and the existing
abort path proves exact stable images plus stable-only cleanup.
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
public_attempts=100
max_errors=0
aws_region=""
alb_timeout_seconds=300
alb_poll_seconds=5
drain_seconds=45
regression_mode="none"
timeout="10m"
execute=false
declare -a values_files=()
declare -a helm_sets=()

while (($#)); do
  case "$1" in
    --context|--namespace|--release|--chart|--stable-api-image|--stable-web-image|--candidate-api-image|--candidate-web-image|--weight|--attempts|--public-attempts|--max-errors|--aws-region|--alb-timeout-seconds|--alb-poll-seconds|--drain-seconds|--regression-mode|--timeout|--values|--helm-set)
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
        --public-attempts) public_attempts="$2" ;;
        --max-errors) max_errors="$2" ;;
        --aws-region) aws_region="$2" ;;
        --alb-timeout-seconds) alb_timeout_seconds="$2" ;;
        --alb-poll-seconds) alb_poll_seconds="$2" ;;
        --drain-seconds) drain_seconds="$2" ;;
        --regression-mode) regression_mode="$2" ;;
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
for value_name in weight attempts public_attempts max_errors alb_timeout_seconds alb_poll_seconds drain_seconds; do
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
if [[ "$stable_api_image" == "$candidate_api_image" || \
      "$stable_web_image" == "$candidate_web_image" ]]; then
  printf '%s\n' 'REFUSING: both candidate images must differ from the captured stable images.' >&2
  exit 2
fi
case "$regression_mode" in
  none|http-error) ;;
  *)
    printf '%s\n' 'REFUSING: --regression-mode must be none or http-error.' >&2
    exit 2
    ;;
esac

for file in "${values_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    printf 'REFUSING: values file does not exist: %s\n' "$file" >&2
    exit 2
  fi
done

if [[ "$execute" == false ]]; then
  printf 'DRY RUN: context=<explicit> namespace=%s release=%s weight=%d attempts=%d public_attempts=%d max_errors=%d\n' \
    "$namespace" "$release" "$weight" "$attempts" "$public_attempts" "$max_errors"
  printf '%s\n' 'DRY RUN: assert the running stable images exactly match the captured baseline.'
  printf '%s\n' 'DRY RUN: for ALB, normalize and reconcile the stable-only action before staging.'
  printf '%s\n' 'DRY RUN: for ALB, pin and verify a 30-second target-group deregistration delay.'
  printf '%s\n' 'DRY RUN: stage weighted traffic; for ALB, prove exact 90/10 reconciliation and public canary handling.'
  if [[ "$regression_mode" == "none" ]]; then
    printf 'DRY RUN: promote candidate, prove ALB pod readiness and exact 100/0 reconciliation, hold %d seconds, then remove canary resources.\n' \
      "$drain_seconds"
  else
    printf 'DRY RUN: require the health gate to block promotion, restore stable at reconciled 100/0, hold %d seconds, then remove canary resources.\n' \
      "$drain_seconds"
  fi
  printf '%s\n' 'DRY RUN: verify canary Deployments, Services, Ingresses, and weighted targets are removed.'
  printf '%s\n' 'DRY RUN: any pre-promotion failure restores stable through reconciled 100/0 before canary removal.'
  if [[ "$regression_mode" == "http-error" ]]; then
    printf '%s\n' 'DRY RUN: inject canary-only HTTP errors and prove exact stable-only rollback.'
  fi
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
      --mode cleanup \
      --expected-canary-weight 0 \
      --timeout-seconds "$alb_timeout_seconds" \
      --poll-seconds "$alb_poll_seconds" \
      --execute
    return
  fi

  kubectl "${kubectl_args[@]}" get ingress bedoux-api >/dev/null
  kubectl "${kubectl_args[@]}" get ingress bedoux-web >/dev/null
}

verify_stable_images() {
  local actual_api_image actual_web_image
  actual_api_image="$(kubectl "${kubectl_args[@]}" get deployment api \
    --output jsonpath='{.spec.template.spec.containers[0].image}')"
  actual_web_image="$(kubectl "${kubectl_args[@]}" get deployment web \
    --output jsonpath='{.spec.template.spec.containers[0].image}')"
  if [[ "$actual_api_image" != "$stable_api_image" || \
        "$actual_web_image" != "$stable_web_image" ]]; then
    printf '%s\n' 'BLOCK: automatic rollback did not restore both captured stable images.' >&2
    return 1
  fi
}

abort_to_stable() {
  printf '%s\n' 'ABORT: restoring captured stable images and requesting 100/0 while retaining canary.' >&2
  helm "${helm_base[@]}" "${stable_values[@]}" "${canary_candidate_values[@]}" \
    --set canary.enabled=true --set canary.weight=0 \
    --set-string "canary.regressionMode=$regression_mode" --set migration.enabled=false
  kubectl "${kubectl_args[@]}" rollout status deployment/api --timeout=5m
  kubectl "${kubectl_args[@]}" rollout status deployment/web --timeout=5m
  if [[ "$alb_rollout" == true ]]; then
    scripts/p13-alb-pod-readiness-gate.sh \
      --context "$context" \
      --namespace "$namespace" \
      --execute
    scripts/p13-alb-reconciliation-gate.sh \
      --context "$context" \
      --namespace "$namespace" \
      --aws-region "$aws_region" \
      --mode promotion \
      --expected-canary-weight 0 \
      --timeout-seconds "$alb_timeout_seconds" \
      --poll-seconds "$alb_poll_seconds" \
      --execute
  fi
  printf 'ABORT DRAIN: holding 100/0 for %d seconds before canary removal.\n' "$drain_seconds" >&2
  sleep "$drain_seconds"
  helm "${helm_base[@]}" "${stable_values[@]}" \
    --set canary.enabled=false --set canary.regressionMode=none --set migration.enabled=false
  kubectl "${kubectl_args[@]}" rollout status deployment/api --timeout=5m
  kubectl "${kubectl_args[@]}" rollout status deployment/web --timeout=5m
  verify_cleanup
  verify_stable_images
  printf '%s\n' 'ROLLBACK_GATE stable_images_restored=true canary_resources_absent=true'
}

alb_rollout=false
if kubectl "${kubectl_args[@]}" get ingress bedoux >/dev/null 2>&1; then
  alb_rollout=true
  # Keep the target-draining interval comfortably below the 300-second ALB
  # reconciliation deadline so an obsolete draining target cannot race the
  # gate boundary. The AWS gate verifies the applied attribute; this desired
  # Helm value alone is not proof.
  helm_base+=(--set ingress.targetGroupDeregistrationDelaySeconds=30)
  stable_target_group_before=""
  stable_target_group_after=""
  if [[ -z "$aws_region" ]]; then
    printf '%s\n' 'REFUSING: --aws-region is required for an ALB rollout.' >&2
    exit 1
  fi
  scripts/p13-alb-pod-readiness-gate.sh \
    --context "$context" \
    --namespace "$namespace" \
    --execute
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
  --set canary.enabled=true --set "canary.weight=$weight" \
  --set-string "canary.regressionMode=$regression_mode"; then
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
  --public-attempts "$public_attempts"
  --max-errors "$max_errors"
  --alb-timeout-seconds "$alb_timeout_seconds"
  --alb-poll-seconds "$alb_poll_seconds"
)
if [[ -n "$aws_region" ]]; then
  gate_args+=(--aws-region "$aws_region")
fi

if ! kubectl "${kubectl_args[@]}" rollout status deployment/api-canary --timeout=5m || \
   ! kubectl "${kubectl_args[@]}" rollout status deployment/web-canary --timeout=5m; then
  if [[ "$stage_succeeded" == true ]]; then
    abort_to_stable
  fi
  exit 1
fi

gate_status=0
gate_output="$(scripts/p13-canary-gate.sh "${gate_args[@]}" --execute)" || gate_status=$?
if [[ -n "$gate_output" ]]; then
  printf '%s\n' "$gate_output"
fi
gate_result_count=0
gate_result_pattern='^CANARY_GATE_RESULT prerequisites=passed reason=http-error-threshold public_http_errors=[0-9]+ direct_http_errors=[0-9]+$'
while IFS= read -r gate_output_line; do
  if [[ "$gate_output_line" =~ $gate_result_pattern ]]; then
    ((gate_result_count += 1))
  fi
done <<<"$gate_output"
if ((gate_status != 0)); then
  if [[ "$stage_succeeded" == true ]]; then
    abort_to_stable
  fi
  if [[ "$regression_mode" == "http-error" && "$gate_status" == 20 && \
        "$gate_result_count" == 1 ]]; then
    printf '%s\n' 'PASS: injected canary regression was blocked and automatic stable-only rollback completed.'
    printf '%s\n' 'T1302_GATE regression=http-error promotion=blocked rollback=stable-only'
    exit 0
  fi
  if [[ "$gate_status" == 20 && "$gate_result_count" != 1 ]]; then
    printf 'BLOCK: canary gate returned reserved status 20 without exactly one attributed result marker (markers=%d); rollback completed and T-1302 evidence is denied.\n' \
      "$gate_result_count" >&2
  elif [[ "$gate_status" == 20 ]]; then
    printf '%s\n' \
      'BLOCK: canary HTTP-error gate blocked promotion outside an authorized regression drill; rollback completed and T-1302 evidence is denied.' >&2
  else
    printf 'BLOCK: canary gate failed for an unrelated reason (status=%d); rollback completed and T-1302 evidence is denied.\n' \
      "$gate_status" >&2
  fi
  exit 1
fi

if [[ "$regression_mode" == "http-error" ]]; then
  printf '%s\n' 'BLOCK: injected canary regression escaped the health gate; refusing promotion.' >&2
  abort_to_stable
  exit 1
fi

printf '%s\n' 'PROMOTE: gate passed; changing the split to stable candidate 100%, canary 0%.'
if ! helm "${helm_base[@]}" "${candidate_values[@]}" "${canary_candidate_values[@]}" \
  --set canary.enabled=true --set canary.weight=0 --set canary.regressionMode=none; then
  abort_to_stable
  exit 1
fi
if ! kubectl "${kubectl_args[@]}" rollout status deployment/api --timeout=5m || \
   ! kubectl "${kubectl_args[@]}" rollout status deployment/web --timeout=5m; then
  abort_to_stable
  exit 1
fi

if [[ "$alb_rollout" == true ]]; then
  if ! scripts/p13-alb-pod-readiness-gate.sh \
       --context "$context" \
       --namespace "$namespace" \
       --execute || \
     ! scripts/p13-alb-reconciliation-gate.sh \
       --context "$context" \
       --namespace "$namespace" \
       --aws-region "$aws_region" \
       --mode promotion \
       --expected-canary-weight 0 \
       --timeout-seconds "$alb_timeout_seconds" \
       --poll-seconds "$alb_poll_seconds" \
       --execute; then
    printf '%s\n' \
      'BLOCK: promotion did not reach ALB-target-ready 100/0; preserving canary resources and refusing drain/cleanup.' >&2
    exit 1
  fi
fi

printf 'DRAIN: holding the 100/0 split for %d seconds before canary removal.\n' "$drain_seconds"
sleep "$drain_seconds"

printf '%s\n' 'CLEANUP: removing zero-weight canary resources.'
helm "${helm_base[@]}" "${candidate_values[@]}" \
  --set canary.enabled=false --set canary.regressionMode=none --set migration.enabled=false
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
