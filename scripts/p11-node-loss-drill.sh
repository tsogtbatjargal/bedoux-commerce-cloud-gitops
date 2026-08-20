#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/p11-node-loss-drill.sh <inspect|drain|recover> --context NAME [options]

Prepare and execute the bounded P11.4 stateless node-loss drill.

  inspect                 Read-only baseline check; prints the safe fault-node candidate.
  drain --node NAME       Dry-run by default; add --execute to cordon/drain NAME.
  recover --node NAME     Dry-run by default; add --execute to uncordon NAME and
                          restart api/web, wait out terminating pods, and perform at
                          most one bounded stateless rebalance per Deployment so
                          normal cross-AZ placement is restored.

Options:
  --context NAME          Required explicit EKS kubectl context.
  --namespace NAME        Application namespace (default: bedoux).
  --node NAME             Exact node for drain/recovery.
  --execute               Perform the requested mutation. Valid only with drain/recover.
  --help                  Show this help.

Safety boundaries:
  - Run only inside an owner-approved P11.4 AWS session with an independent alarm.
  - inspect requires exactly two Ready nodes in two ca-central-1 AZs, healthy api/web
    deployments, usable PDBs, one running postgres pod, the bounded termination
    contract, and an ALB readiness gate on every running web pod.
  - drain refuses the node hosting postgres. P11.4 proves stateless failover only.
  - If drain fails, the script uncordons the selected node before returning failure.
EOF
}

action="${1:-}"
if [[ "$action" == "--help" || "$action" == "-h" ]]; then
  usage
  exit 0
fi
if [[ "$action" != "inspect" && "$action" != "drain" && "$action" != "recover" ]]; then
  usage >&2
  exit 2
fi
shift

context=""
namespace="bedoux"
node=""
execute=false

while (($#)); do
  case "$1" in
    --context)
      if (($# < 2)) || [[ "$2" == --* ]]; then
        usage >&2
        exit 2
      fi
      context="${2:-}"
      shift
      ;;
    --namespace)
      if (($# < 2)) || [[ "$2" == --* ]]; then
        usage >&2
        exit 2
      fi
      namespace="${2:-}"
      shift
      ;;
    --node)
      if (($# < 2)) || [[ "$2" == --* ]]; then
        usage >&2
        exit 2
      fi
      node="${2:-}"
      shift
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

if [[ -z "$context" ]]; then
  printf '%s\n' 'REFUSING: --context is required; never rely on the default kubeconfig context.' >&2
  exit 2
fi
if [[ "$action" == "inspect" && "$execute" == true ]]; then
  printf '%s\n' 'REFUSING: inspect is read-only and does not accept --execute.' >&2
  exit 2
fi
if [[ "$action" != "inspect" && -z "$node" ]]; then
  printf '%s\n' 'REFUSING: --node is required for drain and recover.' >&2
  exit 2
fi

if [[ "$action" != "inspect" && "$execute" == false ]]; then
  printf 'DRY RUN: action=%s context=<explicit> namespace=%s node=%s\n' \
    "$action" "$namespace" "$node"
  if [[ "$action" == "drain" ]]; then
    printf 'DRY RUN: verify the two-AZ baseline and ensure %s does not host postgres\n' "$node"
    printf 'DRY RUN: kubectl cordon %q\n' "$node"
    printf 'DRY RUN: kubectl drain %q --ignore-daemonsets --delete-emptydir-data --timeout=5m\n' "$node"
    printf '%s\n' 'DRY RUN: wait for api/web recovery and assert no running app pod remains on the fault node'
  else
    printf 'DRY RUN: kubectl uncordon %q\n' "$node"
    printf '%s\n' 'DRY RUN: rollout restart api/web and wait for terminating pods to disappear'
    printf '%s\n' 'DRY RUN: if needed, replace at most one pod per Deployment before asserting cross-AZ placement'
  fi
  exit 0
fi

command -v kubectl >/dev/null

mapfile -t nodes < <(kubectl --context "$context" get nodes \
  --output jsonpath='{range .items[*]}{.metadata.name}{"|"}{.metadata.labels.topology\.kubernetes\.io/zone}{"|"}{range .status.conditions[?(@.type=="Ready")]}{.status}{end}{"\n"}{end}')

if ((${#nodes[@]} != 2)); then
  printf 'REFUSING: expected exactly two nodes; found %d.\n' "${#nodes[@]}" >&2
  exit 1
fi

declare -A node_zone=()
declare -A zones=()
for row in "${nodes[@]}"; do
  IFS='|' read -r current_node current_zone current_ready <<<"$row"
  if [[ "$current_ready" != "True" || "$current_zone" != ca-central-1* ]]; then
    printf 'REFUSING: node %s is not Ready in a ca-central-1 AZ.\n' "$current_node" >&2
    exit 1
  fi
  node_zone["$current_node"]="$current_zone"
  zones["$current_zone"]=1
done
if ((${#zones[@]} != 2)); then
  printf 'REFUSING: expected one Ready node in each of two AZs; found %d distinct AZ(s).\n' \
    "${#zones[@]}" >&2
  exit 1
fi

mapfile -t postgres_rows < <(kubectl --context "$context" --namespace "$namespace" get pods \
  --selector app=postgres --field-selector status.phase=Running \
  --output jsonpath='{range .items[*]}{.metadata.name}{"|"}{.spec.nodeName}{"\n"}{end}')
if ((${#postgres_rows[@]} != 1)); then
  printf 'REFUSING: expected exactly one Running postgres pod; found %d.\n' \
    "${#postgres_rows[@]}" >&2
  exit 1
fi
IFS='|' read -r _ postgres_node <<<"${postgres_rows[0]}"
if [[ -z "$postgres_node" ]]; then
  printf '%s\n' 'REFUSING: the Running postgres pod has no node assignment.' >&2
  exit 1
fi
if [[ -z "${node_zone[$postgres_node]:-}" ]]; then
  printf 'REFUSING: postgres is assigned to unverified node %s.\n' "$postgres_node" >&2
  exit 1
fi

assert_app_baseline() {
  local app available disruptions grace prestop
  for app in api web; do
    available="$(kubectl --context "$context" --namespace "$namespace" get deployment "$app" \
      --output jsonpath='{.status.availableReplicas}')"
    disruptions="$(kubectl --context "$context" --namespace "$namespace" get poddisruptionbudget "$app" \
      --output jsonpath='{.status.disruptionsAllowed}')"
    if [[ -z "$available" || "$available" -lt 2 ]]; then
      printf 'REFUSING: deployment/%s has fewer than two available replicas.\n' "$app" >&2
      exit 1
    fi
    if [[ -z "$disruptions" || "$disruptions" -lt 1 ]]; then
      printf 'REFUSING: poddisruptionbudget/%s allows no voluntary disruption.\n' "$app" >&2
      exit 1
    fi
    grace="$(kubectl --context "$context" --namespace "$namespace" get deployment "$app" \
      --output jsonpath='{.spec.template.spec.terminationGracePeriodSeconds}')"
    prestop="$(kubectl --context "$context" --namespace "$namespace" get deployment "$app" \
      --output jsonpath='{.spec.template.spec.containers[0].lifecycle.preStop.exec.command[2]}')"
    if [[ "$grace" != 60 || "$prestop" != 'sleep 45' ]]; then
      printf 'REFUSING: deployment/%s lacks the P11.4 60s grace / 45s preStop contract.\n' \
        "$app" >&2
      exit 1
    fi
  done

  local target_group_attributes
  target_group_attributes="$(kubectl --context "$context" --namespace "$namespace" get ingress bedoux \
    --output jsonpath='{.metadata.annotations.alb\.ingress\.kubernetes\.io/target-group-attributes}')"
  if [[ "$target_group_attributes" != 'deregistration_delay.timeout_seconds=30' ]]; then
    printf '%s\n' 'REFUSING: ingress/bedoux lacks the 30s ALB target deregistration contract.' >&2
    exit 1
  fi

  local pod_name readiness_gates
  local -a web_gate_rows=()
  mapfile -t web_gate_rows < <(kubectl --context "$context" --namespace "$namespace" get pods \
    --selector app=web --field-selector status.phase=Running \
    --output jsonpath='{range .items[*]}{.metadata.name}{"|"}{range .spec.readinessGates[*]}{.conditionType}{","}{end}{"\n"}{end}')
  if ((${#web_gate_rows[@]} < 2)); then
    printf '%s\n' 'REFUSING: fewer than two Running web pods are available for readiness-gate checks.' >&2
    exit 1
  fi
  for row in "${web_gate_rows[@]}"; do
    IFS='|' read -r pod_name readiness_gates <<<"$row"
    if [[ "$readiness_gates" != *target-health.elbv2.k8s.aws/* ]]; then
      printf 'REFUSING: web pod %s lacks an AWS target-health readiness gate.\n' "$pod_name" >&2
      exit 1
    fi
  done
}

safe_fault_node=""
for current_node in "${!node_zone[@]}"; do
  if [[ "$current_node" != "$postgres_node" ]]; then
    safe_fault_node="$current_node"
  fi
done
if [[ -z "$safe_fault_node" ]]; then
  printf '%s\n' 'REFUSING: could not identify a non-postgres fault node.' >&2
  exit 1
fi

stable_app_pods=()
stable_app_nodes=()
stable_app_terminating_count=0

capture_stable_app_pods() {
  local app="$1" row pod_name app_node phase deleting ready
  local -a rows=()

  stable_app_pods=()
  stable_app_nodes=()
  stable_app_terminating_count=0
  mapfile -t rows < <(kubectl --context "$context" --namespace "$namespace" get pods \
    --selector "app=$app" \
    --output jsonpath='{range .items[*]}{.metadata.name}{"|"}{.spec.nodeName}{"|"}{.status.phase}{"|"}{.metadata.deletionTimestamp}{"|"}{range .status.conditions[?(@.type=="Ready")]}{.status}{end}{"\n"}{end}')

  for row in "${rows[@]}"; do
    IFS='|' read -r pod_name app_node phase deleting ready <<<"$row"
    if [[ -n "$deleting" ]]; then
      stable_app_terminating_count=$((stable_app_terminating_count + 1))
      continue
    fi
    if [[ "$phase" == Running && "$ready" == True && -n "$app_node" ]]; then
      stable_app_pods+=("$pod_name")
      stable_app_nodes+=("$app_node")
    fi
  done
}

wait_for_stable_app_pods() {
  local app="$1" timeout_seconds="${2:-120}"
  local deadline=$((SECONDS + timeout_seconds))

  while true; do
    capture_stable_app_pods "$app"
    if ((stable_app_terminating_count == 0 && ${#stable_app_nodes[@]} >= 2)); then
      return 0
    fi
    if ((SECONDS >= deadline)); then
      printf 'FAIL: %s did not settle to at least two non-terminating Ready pods within %ss.\n' \
        "$app" "$timeout_seconds" >&2
      return 1
    fi
    sleep 2
  done
}

stable_app_has_two_zones() {
  local app="$1" app_node
  local -A stable_zones=()

  for app_node in "${stable_app_nodes[@]}"; do
    if [[ -z "${node_zone[$app_node]:-}" ]]; then
      printf 'FAIL: %s has a stable pod on unverified node %s.\n' "$app" "$app_node" >&2
      return 1
    fi
    stable_zones["${node_zone[$app_node]}"]=1
  done
  ((${#stable_zones[@]} == 2))
}

if [[ "$action" == "inspect" ]]; then
  assert_app_baseline
  printf 'Baseline OK: two Ready nodes across two AZs; api/web and both PDBs are healthy.\n'
  printf 'Postgres node: %s (%s)\n' "$postgres_node" "${node_zone[$postgres_node]}"
  printf 'Safe stateless fault candidate: %s (%s)\n' "$safe_fault_node" "${node_zone[$safe_fault_node]}"
  exit 0
fi

if [[ -z "${node_zone[$node]:-}" ]]; then
  printf 'REFUSING: %s is not one of the two verified cluster nodes.\n' "$node" >&2
  exit 1
fi

if [[ "$action" == "drain" ]]; then
  assert_app_baseline
  if [[ "$node" == "$postgres_node" ]]; then
    printf 'REFUSING: %s hosts postgres; P11.4 does not claim database HA.\n' "$node" >&2
    exit 1
  fi

  kubectl --context "$context" cordon "$node"
  if ! kubectl --context "$context" drain "$node" \
    --ignore-daemonsets --delete-emptydir-data --timeout=5m; then
    printf '%s\n' 'Drain failed; uncordoning the selected node for safe recovery.' >&2
    kubectl --context "$context" uncordon "$node"
    exit 1
  fi

  for app in api web; do
    kubectl --context "$context" --namespace "$namespace" rollout status \
      "deployment/$app" --timeout=5m
    mapfile -t app_nodes < <(kubectl --context "$context" --namespace "$namespace" get pods \
      --selector "app=$app" --field-selector status.phase=Running \
      --output jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}')
    if ((${#app_nodes[@]} < 2)); then
      printf 'FAIL: %s has fewer than two running pods after drain.\n' "$app" >&2
      exit 1
    fi
    for app_node in "${app_nodes[@]}"; do
      if [[ "$app_node" == "$node" ]]; then
        printf 'FAIL: %s still has a running pod on drained node %s.\n' "$app" "$node" >&2
        exit 1
      fi
    done
  done
  printf 'Drain recovery OK: api/web are Ready on the surviving AZ; keep k6 running.\n'
  exit 0
fi

kubectl --context "$context" uncordon "$node"
kubectl --context "$context" wait --for=condition=Ready "node/$node" --timeout=3m
kubectl --context "$context" --namespace "$namespace" rollout restart deployment/api deployment/web

for app in api web; do
  kubectl --context "$context" --namespace "$namespace" rollout status \
    "deployment/$app" --timeout=5m
  wait_for_stable_app_pods "$app"
  if ! stable_app_has_two_zones "$app"; then
    rebalance_pod="${stable_app_pods[0]}"
    printf 'Recovery rebalance: replacing one %s pod (%s) after terminating pods settled.\n' \
      "$app" "$rebalance_pod"
    kubectl --context "$context" --namespace "$namespace" delete pod "$rebalance_pod" \
      --wait=false
    kubectl --context "$context" --namespace "$namespace" wait --for=delete \
      "pod/$rebalance_pod" --timeout=2m
    kubectl --context "$context" --namespace "$namespace" rollout status \
      "deployment/$app" --timeout=5m
    wait_for_stable_app_pods "$app"
  fi
  if ! stable_app_has_two_zones "$app"; then
    printf 'FAIL: %s did not return to two-AZ placement after recovery.\n' "$app" >&2
    exit 1
  fi
done

printf 'Recovery OK: fault node is schedulable and api/web are Ready across both AZs.\n'
