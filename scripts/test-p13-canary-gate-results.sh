#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/bin"
touch "$test_root/access.log"

cat >"$test_root/bin/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

args=" $* "
case "$args" in
  *" get deployment api-canary --output jsonpath={.spec.replicas} "*|\
  *" get deployment api-canary --output jsonpath={.status.availableReplicas} "*|\
  *" get deployment web-canary --output jsonpath={.spec.replicas} "*|\
  *" get deployment web-canary --output jsonpath={.status.availableReplicas} "*)
    printf '%s' '1'
    ;;
  *" get deployment api-canary --output jsonpath={.spec.template.spec.containers[0].image} "*)
    printf '%s' "$P13_EXPECTED_API_IMAGE"
    ;;
  *" get deployment web-canary --output jsonpath={.spec.template.spec.containers[0].image} "*)
    printf '%s' "$P13_EXPECTED_WEB_IMAGE"
    ;;
  *" get pods --selector app=api-canary "*|*" get pods --selector app=web-canary "*)
    printf '%s\n' 'pod/mock'
    ;;
  *" get ingress bedoux "*)
    exit 1
    ;;
  *" get ingress bedoux-api-canary "*|*" get ingress bedoux-web-canary "*)
    printf '%s' '10'
    ;;
  *" logs deployment/web-canary "*)
    cat "$P13_GATE_ACCESS_LOG"
    ;;
  *" exec deployment/web-canary -- wget "*)
    url="${!#}"
    if [[ "$url" == *'/api/products?'* ]]; then
      printf '%s\n' '[{"id":1}]'
      exit 0
    fi
    case "$P13_GATE_SAMPLE_MODE" in
      http-error)
        printf '127.0.0.1 - - "GET %s HTTP/1.1" 404 0\n' "${url#http://127.0.0.1:8080}" \
          >>"$P13_GATE_ACCESS_LOG"
        exit 1
        ;;
      tooling-error)
        printf '127.0.0.1 - - "GET %s HTTP/1.1" 200 0\n' "${url#http://127.0.0.1:8080}" \
          >>"$P13_GATE_ACCESS_LOG"
        exit 1
        ;;
      pass)
        printf '127.0.0.1 - - "GET %s HTTP/1.1" 200 0\n' "${url#http://127.0.0.1:8080}" \
          >>"$P13_GATE_ACCESS_LOG"
        printf '%s\n' '{"status":"ok"}'
        ;;
    esac
    ;;
  *)
    printf 'unexpected kubectl mock invocation: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$test_root/bin/kubectl"

expected_api="localhost/bedoux-api:candidate"
expected_web="localhost/bedoux-web:candidate"

run_gate() {
  local mode="$1"
  local output_file="$2"
  : >"$test_root/access.log"
  set +e
  PATH="$test_root/bin:$PATH" \
    P13_EXPECTED_API_IMAGE="$expected_api" \
    P13_EXPECTED_WEB_IMAGE="$expected_web" \
    P13_GATE_ACCESS_LOG="$test_root/access.log" \
    P13_GATE_SAMPLE_MODE="$mode" \
    "$repo_root/scripts/p13-canary-gate.sh" \
      --context kind-p13-test \
      --expected-api-image "$expected_api" \
      --expected-web-image "$expected_web" \
      --attempts 2 \
      --max-errors 0 \
      --execute >"$output_file" 2>&1
  gate_status=$?
  set -e
}

http_output="$test_root/http-error.out"
run_gate http-error "$http_output"
if ((gate_status != 20)); then
  printf 'expected HTTP-error threshold status 20, got %d\n' "$gate_status" >&2
  cat "$http_output" >&2
  exit 1
fi
grep -Fq 'CANARY_GATE attempts=2 errors=2 error_rate=1.0000 log_hits=2 http_errors=2' "$http_output"
grep -Fq 'CANARY_GATE_RESULT prerequisites=passed reason=http-error-threshold' "$http_output"

tooling_output="$test_root/tooling-error.out"
run_gate tooling-error "$tooling_output"
if ((gate_status != 1)); then
  printf 'expected unrelated tooling failure status 1, got %d\n' "$gate_status" >&2
  cat "$tooling_output" >&2
  exit 1
fi
grep -Fq 'CANARY_GATE attempts=2 errors=2 error_rate=1.0000 log_hits=2 http_errors=0' "$tooling_output"
grep -Fq 'were not fully attributable to HTTP error responses' "$tooling_output"
if grep -Fq 'CANARY_GATE_RESULT' "$tooling_output"; then
  printf '%s\n' 'tooling failure emitted a false-positive HTTP-error result' >&2
  exit 1
fi

pass_output="$test_root/pass.out"
run_gate pass "$pass_output"
if ((gate_status != 0)); then
  printf 'expected clean gate status 0, got %d\n' "$gate_status" >&2
  cat "$pass_output" >&2
  exit 1
fi
grep -Fq 'CANARY_GATE attempts=2 errors=0 error_rate=0.0000 log_hits=2 http_errors=0' "$pass_output"
grep -Fq 'PASS: exact canary images' "$pass_output"

printf '%s\n' 'p13 canary gate result classification mocks OK'
