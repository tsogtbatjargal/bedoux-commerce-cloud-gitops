#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/p13-alb-pod-readiness-gate.sh --context NAME [options]
       [--dry-run|--execute]

Fail-closed proof that every active stable web pod has a healthy AWS Load Balancer
Controller target-health readiness gate. The default is --dry-run.

Required:
  --context NAME              Explicit kubectl context.

Options:
  --namespace NAME            Namespace (default: bedoux).
  --selector SELECTOR         Stable web pod selector (default: app=web).
  --dry-run                   Print checks without contacting Kubernetes.
  --execute                   Perform the read-only pod check.
  --help                      Show this help.

This assertion proves actual webhook injection and a True target-health condition;
it does not infer either from the namespace label or Kubernetes Ready alone.
EOF
}

context=""
namespace="bedoux"
selector="app=web"
execute=false

while (($#)); do
  case "$1" in
    --context|--namespace|--selector)
      if (($# < 2)) || [[ "$2" == --* ]]; then
        usage >&2
        exit 2
      fi
      case "$1" in
        --context) context="$2" ;;
        --namespace) namespace="$2" ;;
        --selector) selector="$2" ;;
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

if [[ -z "$context" || -z "$namespace" || -z "$selector" ]]; then
  printf '%s\n' 'REFUSING: --context, --namespace, and --selector must be non-empty.' >&2
  exit 2
fi

if [[ "$execute" == false ]]; then
  printf 'DRY RUN: context=<explicit> namespace=%s selector=%s\n' "$namespace" "$selector"
  printf '%s\n' 'DRY RUN: require every active pod to be Running and Ready with a True target-health.elbv2.k8s.aws readiness gate.'
  exit 0
fi

command -v kubectl >/dev/null
command -v python >/dev/null

# M4: scripts/lib/gate_checks.py replaces this file's inline embedded-Python assertion. This
# is a one-shot check with no retry loop, so the module's own stderr diagnostic (printed
# on any failure now that nothing suppresses it) is the whole win -- no exit-code
# branching is needed here the way the polling p13-alb-reconciliation-gate.sh needs it.
pods_json="$(kubectl --context "$context" --namespace "$namespace" get pods \
  --selector "$selector" --output json)"
active_count="$(python scripts/lib/gate_checks.py pod-readiness-gate <<<"$pods_json")" || {
  printf '%s\n' 'BLOCK: active stable web pods lack a healthy ALB target-health readiness gate.' >&2
  exit 1
}

printf 'ALB_POD_READINESS_GATE pods=%d injected=true target_health=true\n' "$active_count"
printf '%s\n' 'PASS: every active stable web pod is ALB-target-ready.'
