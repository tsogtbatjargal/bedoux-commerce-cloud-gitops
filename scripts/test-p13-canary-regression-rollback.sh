#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/bin" "$test_root/scripts"
cp "$repo_root/scripts/p13-canary-rollout.sh" "$test_root/scripts/"

cat >"$test_root/bin/helm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
args=" $* "
if [[ "$args" == *" canary.enabled=true "* && "$args" == *" canary.weight=10 "* ]]; then
  printf '%s\n' 'HELM_STAGE regression=http-error' >>"$P13_TEST_LOG"
elif [[ "$args" == *" canary.enabled=true "* && "$args" == *" canary.weight=0 "* ]]; then
  printf '%s\n' 'HELM_ABORT_100_0' >>"$P13_TEST_LOG"
elif [[ "$args" == *" canary.enabled=false "* ]]; then
  printf '%s\n' 'HELM_CLEANUP_STABLE_ONLY' >>"$P13_TEST_LOG"
fi
EOF

cat >"$test_root/bin/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
tokens=("$@")
for ((index = 0; index < ${#tokens[@]}; index++)); do
  case "${tokens[index]}" in
    rollout)
      exit 0
      ;;
    get)
      resource="${tokens[index + 1]:-}"
      name="${tokens[index + 2]:-}"
      case "$resource/$name" in
        deployment/api)
          printf '%s' "$P13_STABLE_API_IMAGE"
          exit 0
          ;;
        deployment/web)
          printf '%s' "$P13_STABLE_WEB_IMAGE"
          exit 0
          ;;
        ingress/bedoux)
          # No ALB Ingress in this local state-machine proof.
          exit 1
          ;;
        ingress/bedoux-api|ingress/bedoux-web)
          exit 0
          ;;
        deployment/api-canary|deployment/web-canary|service/api-canary|service/web-canary|configmap/web-canary-config|ingress/bedoux-api-canary|ingress/bedoux-web-canary)
          # --ignore-not-found cleanup assertions expect empty successful output.
          exit 0
          ;;
      esac
      ;;
  esac
done
printf 'unexpected kubectl mock invocation: %s\n' "$*" >&2
exit 1
EOF

cat >"$test_root/bin/sleep" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'SLEEP %s\n' "$1" >>"$P13_TEST_LOG"
EOF

cat >"$test_root/scripts/p13-canary-gate.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${P13_GATE_RESULT:-expected}" in
  pass)
    printf '%s\n' 'GATE_UNEXPECTED_PASS' >>"$P13_TEST_LOG"
    exit 0
    ;;
  expected)
    printf '%s\n' 'GATE_EXPECTED_HTTP_ERROR_BLOCK' >>"$P13_TEST_LOG"
    printf '%s\n' \
      'CANARY_GATE_RESULT prerequisites=passed reason=http-error-threshold public_http_errors=1 direct_http_errors=20'
    exit 20
    ;;
  unattributed)
    printf '%s\n' 'GATE_UNATTRIBUTED_STATUS_20' >>"$P13_TEST_LOG"
    exit 20
    ;;
  unrelated)
    printf '%s\n' 'GATE_UNRELATED_BLOCK' >>"$P13_TEST_LOG"
    exit 1
    ;;
esac
exit 2
EOF

chmod +x "$test_root/bin/helm" "$test_root/bin/kubectl" "$test_root/bin/sleep" \
  "$test_root/scripts/p13-canary-rollout.sh" "$test_root/scripts/p13-canary-gate.sh"

stable_api="localhost/bedoux-api:stable"
stable_web="localhost/bedoux-web:stable"
candidate_api="localhost/bedoux-api:candidate"
candidate_web="localhost/bedoux-web:candidate"

run_drill() {
  local result="$1"
  local log_file="$2"
  local output_file="$3"
  local regression_mode="${4:-http-error}"
  local candidate_mode="${5:-distinct}"
  local candidate_api_arg="$candidate_api"
  local candidate_web_arg="$candidate_web"
  if [[ "$candidate_mode" == "same" ]]; then
    candidate_api_arg="$stable_api"
    candidate_web_arg="$stable_web"
  fi
  (
    cd "$test_root"
    PATH="$test_root/bin:$PATH" \
      P13_TEST_LOG="$log_file" \
      P13_GATE_RESULT="$result" \
      P13_STABLE_API_IMAGE="$stable_api" \
      P13_STABLE_WEB_IMAGE="$stable_web" \
      scripts/p13-canary-rollout.sh \
        --context kind-p13-test \
        --stable-api-image "$stable_api" \
        --stable-web-image "$stable_web" \
        --candidate-api-image "$candidate_api_arg" \
        --candidate-web-image "$candidate_web_arg" \
        --regression-mode "$regression_mode" \
        --drain-seconds 0 \
        --execute
  ) >"$output_file" 2>&1
}

blocked_log="$test_root/blocked.log"
blocked_output="$test_root/blocked.out"
run_drill expected "$blocked_log" "$blocked_output"
grep -Fxq 'HELM_STAGE regression=http-error' "$blocked_log"
grep -Fxq 'GATE_EXPECTED_HTTP_ERROR_BLOCK' "$blocked_log"
grep -Fxq 'HELM_ABORT_100_0' "$blocked_log"
grep -Fxq 'HELM_CLEANUP_STABLE_ONLY' "$blocked_log"
blocked_stage_line="$(grep -nFx 'HELM_STAGE regression=http-error' "$blocked_log" | cut -d: -f1)"
blocked_gate_line="$(grep -nFx 'GATE_EXPECTED_HTTP_ERROR_BLOCK' "$blocked_log" | cut -d: -f1)"
blocked_abort_line="$(grep -nFx 'HELM_ABORT_100_0' "$blocked_log" | cut -d: -f1)"
blocked_cleanup_line="$(grep -nFx 'HELM_CLEANUP_STABLE_ONLY' "$blocked_log" | cut -d: -f1)"
if ! ((blocked_stage_line < blocked_gate_line && blocked_gate_line < blocked_abort_line && \
      blocked_abort_line < blocked_cleanup_line)); then
  printf '%s\n' 'expected gate block did not precede 100/0 abort and stable-only cleanup' >&2
  exit 1
fi
grep -Fq 'ROLLBACK_GATE stable_images_restored=true canary_resources_absent=true' "$blocked_output"
grep -Fq 'T1302_GATE regression=http-error promotion=blocked rollback=stable-only' "$blocked_output"
if grep -Fq 'PROMOTE:' "$blocked_output"; then
  printf '%s\n' 'regression drill attempted promotion after the expected gate block' >&2
  exit 1
fi

# A clean post-merge retry builds the same exact main SHA as its baseline. The
# http-error drill is intentionally configuration-only, so identical image
# digests must still exercise the attributed block and rollback contract.
same_image_log="$test_root/same-image.log"
same_image_output="$test_root/same-image.out"
run_drill expected "$same_image_log" "$same_image_output" http-error same
grep -Fxq 'HELM_STAGE regression=http-error' "$same_image_log"
grep -Fxq 'HELM_ABORT_100_0' "$same_image_log"
grep -Fxq 'HELM_CLEANUP_STABLE_ONLY' "$same_image_log"
grep -Fq 'T1302_GATE regression=http-error promotion=blocked rollback=stable-only' \
  "$same_image_output"

# Ordinary progressive delivery still requires genuinely different candidate
# references; only the explicitly authorized configuration regression may reuse
# the captured stable digests.
same_image_normal_log="$test_root/same-image-normal.log"
same_image_normal_output="$test_root/same-image-normal.out"
if run_drill expected "$same_image_normal_log" "$same_image_normal_output" none same; then
  printf '%s\n' 'ordinary rollout accepted candidate images equal to stable' >&2
  exit 1
fi
grep -Fq 'ordinary canary candidate images must differ' "$same_image_normal_output"
if [[ -s "$same_image_normal_log" ]]; then
  printf '%s\n' 'ordinary same-image refusal mutated the mocked release' >&2
  exit 1
fi

unrelated_log="$test_root/unrelated.log"
unrelated_output="$test_root/unrelated.out"
if run_drill unrelated "$unrelated_log" "$unrelated_output"; then
  printf '%s\n' 'regression drill succeeded after an unrelated gate failure' >&2
  exit 1
fi
grep -Fxq 'GATE_UNRELATED_BLOCK' "$unrelated_log"
grep -Fxq 'HELM_ABORT_100_0' "$unrelated_log"
grep -Fxq 'HELM_CLEANUP_STABLE_ONLY' "$unrelated_log"
grep -Fq 'ROLLBACK_GATE stable_images_restored=true canary_resources_absent=true' "$unrelated_output"
grep -Fq 'T-1302 evidence is denied' "$unrelated_output"
if grep -Fq 'T1302_GATE' "$unrelated_output"; then
  printf '%s\n' 'unrelated gate failure emitted false-positive T-1302 evidence' >&2
  exit 1
fi
if grep -Fq 'PROMOTE:' "$unrelated_output"; then
  printf '%s\n' 'unrelated gate failure reached the promotion mutation' >&2
  exit 1
fi

unattributed_log="$test_root/unattributed.log"
unattributed_output="$test_root/unattributed.out"
if run_drill unattributed "$unattributed_log" "$unattributed_output"; then
  printf '%s\n' 'regression drill trusted an unattributed reserved status 20' >&2
  exit 1
fi
grep -Fxq 'GATE_UNATTRIBUTED_STATUS_20' "$unattributed_log"
grep -Fxq 'HELM_ABORT_100_0' "$unattributed_log"
grep -Fxq 'HELM_CLEANUP_STABLE_ONLY' "$unattributed_log"
grep -Fq 'reserved status 20 without exactly one attributed result marker' "$unattributed_output"
if grep -Fq 'T1302_GATE' "$unattributed_output"; then
  printf '%s\n' 'unattributed status 20 emitted false-positive T-1302 evidence' >&2
  exit 1
fi

normal_regression_log="$test_root/normal-regression.log"
normal_regression_output="$test_root/normal-regression.out"
if run_drill expected "$normal_regression_log" "$normal_regression_output" none; then
  printf '%s\n' 'normal rollout succeeded after a correlated HTTP-error gate block' >&2
  exit 1
fi
grep -Fxq 'HELM_ABORT_100_0' "$normal_regression_log"
grep -Fxq 'HELM_CLEANUP_STABLE_ONLY' "$normal_regression_log"
grep -Fq 'canary HTTP-error gate blocked promotion outside an authorized regression drill' \
  "$normal_regression_output"
if grep -Fq 'T1302_GATE' "$normal_regression_output"; then
  printf '%s\n' 'normal rollout emitted T-1302 drill evidence' >&2
  exit 1
fi

escaped_log="$test_root/escaped.log"
escaped_output="$test_root/escaped.out"
if run_drill pass "$escaped_log" "$escaped_output"; then
  printf '%s\n' 'regression drill succeeded even though the gate accepted the injected error' >&2
  exit 1
fi
grep -Fxq 'GATE_UNEXPECTED_PASS' "$escaped_log"
grep -Fxq 'HELM_ABORT_100_0' "$escaped_log"
grep -Fxq 'HELM_CLEANUP_STABLE_ONLY' "$escaped_log"
escaped_gate_line="$(grep -nFx 'GATE_UNEXPECTED_PASS' "$escaped_log" | cut -d: -f1)"
escaped_abort_line="$(grep -nFx 'HELM_ABORT_100_0' "$escaped_log" | cut -d: -f1)"
escaped_cleanup_line="$(grep -nFx 'HELM_CLEANUP_STABLE_ONLY' "$escaped_log" | cut -d: -f1)"
if ! ((escaped_gate_line < escaped_abort_line && escaped_abort_line < escaped_cleanup_line)); then
  printf '%s\n' 'escaped regression was not aborted and cleaned up in order' >&2
  exit 1
fi
grep -Fq 'BLOCK: injected canary regression escaped the health gate; refusing promotion.' "$escaped_output"
if grep -Fq 'PROMOTE:' "$escaped_output"; then
  printf '%s\n' 'escaped regression reached the promotion mutation' >&2
  exit 1
fi

printf '%s\n' 'p13 canary regression rollback mocks OK'
