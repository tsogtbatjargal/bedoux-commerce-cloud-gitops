#!/usr/bin/env bash
# Local kind-cluster diagnostics: pods/nodes/events across all namespaces,
# then logs + describe for anything not Running/Completed. Read-only.
#
# Usage:
#   scripts/k8s-diag.sh [-n NAMESPACE] [-c CONTEXT]
#
#   -n NAMESPACE   only look at this namespace (default: all namespaces)
#   -c CONTEXT     kubectl context to use (default: current context)
#   -h             show this help

set -uo pipefail

namespace=""
context=""

while getopts "n:c:h" opt; do
  case "${opt}" in
    n) namespace="${OPTARG}" ;;
    c) context="${OPTARG}" ;;
    h)
      sed -n '2,10p' "$0"
      exit 0
      ;;
    *)
      sed -n '2,10p' "$0"
      exit 1
      ;;
  esac
done

kctl=(kubectl)
[[ -n "${context}" ]] && kctl+=(--context "${context}")

ns_flag=(-A)
[[ -n "${namespace}" ]] && ns_flag=(-n "${namespace}")

hr() { printf '\n=== %s ===\n' "$1"; }

hr "context"
"${kctl[@]}" config current-context 2>&1

hr "nodes"
"${kctl[@]}" get nodes -o wide 2>&1

hr "pods (${namespace:-all namespaces})"
"${kctl[@]}" get pods "${ns_flag[@]}" -o wide 2>&1

hr "recent events, sorted by time (${namespace:-all namespaces})"
"${kctl[@]}" get events "${ns_flag[@]}" --sort-by=.lastTimestamp 2>&1 | tail -n 40

# Find pods that are not Running/Completed and dig into each one.
hr "unhealthy pods — describe + logs (current and previous container, if any)"
bad_pods="$("${kctl[@]}" get pods "${ns_flag[@]}" --no-headers 2>/dev/null \
  | awk '$4 !~ /^(Running|Completed)$/ {print $1"/"$2}')"

if [[ -z "${bad_pods}" ]]; then
  echo "none found — every pod is Running or Completed"
else
  while IFS='/' read -r pod_ns pod_name; do
    [[ -n "${namespace}" ]] && pod_ns="${namespace}"
    hr "describe ${pod_ns}/${pod_name}"
    "${kctl[@]}" -n "${pod_ns}" describe pod "${pod_name}" 2>&1 | tail -n 30

    hr "logs ${pod_ns}/${pod_name} (current container)"
    "${kctl[@]}" -n "${pod_ns}" logs "${pod_name}" --all-containers --tail=50 2>&1

    hr "logs ${pod_ns}/${pod_name} (previous container, if it crashed/restarted)"
    "${kctl[@]}" -n "${pod_ns}" logs "${pod_name}" --all-containers --previous --tail=50 2>&1
  done <<< "${bad_pods}"
fi

hr "node/pod resource usage (requires metrics-server; may be unavailable on kind)"
"${kctl[@]}" top nodes 2>&1
"${kctl[@]}" top pods "${ns_flag[@]}" 2>&1
