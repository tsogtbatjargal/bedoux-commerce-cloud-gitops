#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/gitops-suspend-reconciliation.sh --context NAME --root-app NAME
       --child-apps NAME[,NAME...] [options] [--dry-run|--execute]

Suspend Argo CD reconciliation before teardown or a Git-repair window, per
Application, in this order: (1) disable auto-sync FIRST, before checking for any
in-flight or queued operation — this closes the race where a new operation could
start between "no operation found" and "automation disabled"; (2) wait for, and if
necessary force-terminate, any operation that was already running or queued at the
moment automation was disabled; (3) re-verify automation is off AND no active/queued
operation remains, from a freshly re-fetched, shape-validated response. Root is
fully suspended and verified before any child is touched, so a live root cannot
re-enable a child.

The default is --dry-run: prints the exact argocd/jq commands this run would issue,
contacts nothing, and requires no installed CLI or cluster access. --execute
requires the argocd CLI, jq, a valid kubeconfig context and an authenticated argocd
session; it is not runnable against a real cluster until GO-3 installs Argo CD.
Its command-failure and mock-cluster handling IS covered locally without a cluster —
see scripts/test-gitops-suspend-reconciliation.sh.

Required:
  --context NAME               Explicit kubectl context. No current-context guessing.
  --root-app NAME               Exact root/bootstrap Application name.
  --child-apps NAME[,NAME...]   Exact, explicit child Application allowlist. No
                                 namespace-wide "all Applications" query is issued.

Options:
  --argocd-context NAME         Explicit argocd CLI context/server alias, if it
                                 differs from --context (default: same as --context).
  --cmd-timeout-seconds N        Per-command deadline for every individual argocd
                                 or jq invocation (default: 20). A hung call fails
                                 that call, not the whole script.
  --op-wait-timeout-seconds N   Bounded wait for an active/queued operation to clear
                                 before this script force-terminates it (default:
                                 120).
  --op-poll-seconds N           Poll interval while waiting (default: 5).
  --term-wait-timeout-seconds N Bounded wait, AFTER force-terminating, to confirm
                                 the operation actually cleared before this script
                                 proceeds (default: 60). Still not clear at the
                                 deadline: refuse to suspend that Application.
  --verify-timeout-seconds N    Bounded wait to confirm, from a fresh query, that
                                 automation is off AND no active/queued operation
                                 remains (default: 60).
  --dry-run                     Print the command sequence without contacting a
                                 cluster or the argocd API (default).
  --execute                     Perform the suspension against the explicit context.
  --help                        Show this help.

Every argocd/jq invocation is individually checked for a zero exit status. A jq
parse/processing failure is ALWAYS a hard error, distinct from a field being
legitimately null/absent (which jq reports with exit 0 and an explicit sentinel
value here — never inferred from a nonzero exit code, which was a real defect in an
earlier version: a broken jq call could previously be misread as "field absent,
therefore suspended"). Every response is checked for COMPLETE Application-shaped
JSON (matching .metadata.name AND a mandatory .spec object; .status stays
genuinely optional, since a real never-synced Application can lack one) before any
field is trusted; a malformed, truncated (e.g. missing .spec entirely) or
wrong-app response is refused, never silently treated as success.

Scope boundary (read before use):
  - This script ONLY suspends Argo reconciliation. It does not remove Ingress, does
    not stop the AWS Load Balancer Controller, and does not delete any workload,
    PVC or namespace. Those stay sequenced exactly as
    docs/runbooks/gitops-recovery.md's Teardown section (steps 3-5) already
    describes; this script satisfies that section's step 2 only.
  - This script does NOT quiesce Argo Rollouts. Progressive delivery is GO-6 scope
    and not installed as of GO-1/GO-3; a Rollouts-aware quiesce step is reserved
    for that later design and must not be assumed equivalent to this script.
  - Suspension here means each Application's syncPolicy no longer auto-syncs or
    self-heals, and has no active or queued operation at verification time; it does
    not delete the Application resource, and it does not by itself prove a
    subsequent cluster/controller restart won't restore automation. A
    restart/no-recreation test against a live cluster is GO-3/GO-5 evidence.

Exit status:
  0 only if the root was suspended and verified, and every named child was
  suspended and verified within its timeout. Any command failure, any malformed
  response, any Application left unverified, or any operation that never clears is
  a loud failure (non-zero exit, no partial success claimed, no child touched if
  root failed).
EOF
}

context=""
argocd_context=""
root_app=""
declare -a child_apps=()
cmd_timeout_seconds=20
op_wait_timeout_seconds=120
op_poll_seconds=5
term_wait_timeout_seconds=60
verify_timeout_seconds=60
execute=false

split_csv() {
  local IFS=','
  read -r -a child_apps <<<"$1"
}

while (($#)); do
  case "$1" in
    --context|--argocd-context|--root-app|--child-apps|--cmd-timeout-seconds|--op-wait-timeout-seconds|--op-poll-seconds|--term-wait-timeout-seconds|--verify-timeout-seconds)
      if (($# < 2)) || [[ "$2" == --* ]]; then
        usage >&2
        exit 2
      fi
      case "$1" in
        --context) context="$2" ;;
        --argocd-context) argocd_context="$2" ;;
        --root-app) root_app="$2" ;;
        --child-apps) split_csv "$2" ;;
        --cmd-timeout-seconds) cmd_timeout_seconds="$2" ;;
        --op-wait-timeout-seconds) op_wait_timeout_seconds="$2" ;;
        --op-poll-seconds) op_poll_seconds="$2" ;;
        --term-wait-timeout-seconds) term_wait_timeout_seconds="$2" ;;
        --verify-timeout-seconds) verify_timeout_seconds="$2" ;;
      esac
      shift 2
      ;;
    --dry-run) execute=false; shift ;;
    --execute) execute=true; shift ;;
    --help) usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$context" || -z "$root_app" || ${#child_apps[@]} -eq 0 ]]; then
  echo "Error: --context, --root-app and --child-apps are all required." >&2
  usage >&2
  exit 2
fi

if [[ -z "$argocd_context" ]]; then
  argocd_context="$context"
fi

for n in "$cmd_timeout_seconds" "$op_wait_timeout_seconds" "$op_poll_seconds" "$term_wait_timeout_seconds" "$verify_timeout_seconds"; do
  if ! [[ "$n" =~ ^[0-9]+$ ]] || [[ "$n" -le 0 ]]; then
    echo "Error: timeout/poll values must be positive integers (got: $n)." >&2
    exit 2
  fi
done

log() { printf '[gitops-suspend] %s\n' "$1" >&2; } # stderr: never let a diagnostic
# log line get silently captured into a caller's $(...) return-value substitution
# (a real bug found in review — get_operation_state's own error message was being
# absorbed into wait_for_quiescence's "$state" variable instead of appearing at all)

# Every argocd call goes through here: explicit timeout, explicit exit-code check,
# stdout/stderr both captured so a failure is diagnosable. Never called bare.
run_argocd() {
  local desc="$1"
  shift
  local out rc
  if out=$(timeout "$cmd_timeout_seconds" argocd "$@" --context "$argocd_context" 2>&1); then
    printf '%s' "$out"
    return 0
  fi
  rc=$?
  log "ERROR: $desc failed (exit $rc, timeout=${cmd_timeout_seconds}s): $out"
  return 1
}

# Confirms $1 is valid, COMPLETE Application-shaped JSON for the named app ($2)
# before any field from it is trusted. A jq failure here (malformed JSON) and a
# shape mismatch are both treated as "cannot trust this response" — deliberately
# conflated, since both lead to the same required action: refuse.
#
# Corrected per Codex's third GO-1 review (docs/PROGRESS.md session log
# 2026-09-09T14:37:25-06:00): the prior check only required .kind/.metadata.name to
# match, so a truncated/incomplete response like {"metadata":{"name":"root"}} (no
# .spec at all) was accepted as shape-valid, and every downstream field lookup then
# legitimately reported "null" for a field that was never actually queried — an
# incomplete response was indistinguishable from a genuinely quiesced Application.
# .spec is now MANDATORY (a real Application always has one; its total absence
# means the response is truncated/wrong, not that the Application has no spec).
# .status, by contrast, stays genuinely OPTIONAL — a real, valid, never-synced
# Application can legitimately have no .status at all — but IF present, and IF
# .status.operationState/.operation are present, their types are validated so a
# malformed (non-object/non-string) value is refused rather than silently
# stringified/misread by a later jq filter.
validate_application_shape() {
  local json="$1" app="$2"
  printf '%s' "$json" | timeout "$cmd_timeout_seconds" jq -e --arg app "$app" '
    (.kind == "Application" or .kind == null)
    and .metadata.name == $app
    and (.spec != null and (.spec | type) == "object")
    and (.spec.syncPolicy == null or (.spec.syncPolicy | type) == "object")
    and (.operation == null or (.operation | type) == "object")
    and (.status == null or (.status | type) == "object")
    and (.status.operationState == null or (.status.operationState | type) == "object")
    and (.status.operationState.phase == null or (.status.operationState.phase | type) == "string")
  ' >/dev/null 2>&1
}

# Extracts a STRING-valued field (e.g. operationState.phase). Returns 1 (hard
# failure — jq itself could not process the input) or 0 with the raw string on
# stdout — "<ABSENT>" is the explicit sentinel for a legitimately null/missing
# field, never inferred from a nonzero exit code.
extract_string_field() {
  local json="$1" filter="$2"
  local out
  if ! out=$(printf '%s' "$json" | timeout "$cmd_timeout_seconds" jq -r "($filter) // \"<ABSENT>\"" 2>&1); then
    log "ERROR: jq failed extracting $filter: $out"
    return 1
  fi
  printf '%s' "$out"
  return 0
}

# Returns 1 (hard failure) or 0 with "true"/"false" on stdout: "true" iff the field
# at $2 is JSON null or the path does not exist. Uses an explicit `== null`
# comparison rather than jq's `-e`/`//` truthiness (which also treats a literal
# `false` value as "absent") so presence/absence is never conflated with a jq
# processing failure, and never conflated with an explicit false.
field_is_null() {
  local json="$1" filter="$2"
  local out
  if ! out=$(printf '%s' "$json" | timeout "$cmd_timeout_seconds" jq -c "($filter) == null" 2>&1); then
    log "ERROR: jq failed evaluating null-check on $filter: $out"
    return 1
  fi
  printf '%s' "$out"
  return 0
}

is_terminal_phase() {
  case "$1" in
    None|"<ABSENT>"|Succeeded|Failed|Error) return 0 ;;
    *) return 1 ;; # Running, Terminating, empty, or anything unrecognized: not safe
  esac
}

# Fetches, shape-validates, and returns "phase|operation_absent" for $app, or
# returns 1 on any hard failure (command, shape, or parse). operation_absent is
# "true"/"false" from field_is_null on .operation — the REQUESTED/queued operation
# field, distinct from .status.operationState which reflects the last-started one.
# Examining both is required: a queued-but-not-yet-started operation would be
# invisible if only operationState were checked.
get_operation_state() {
  local app="$1"
  local json phase operation_absent
  if ! json=$(run_argocd "app get $app (operation state)" app get "$app" -o json); then
    return 1
  fi
  if ! validate_application_shape "$json" "$app"; then
    log "ERROR: response for $app is not valid Application-shaped JSON (or metadata.name mismatch); refusing to trust it"
    return 1
  fi
  if ! phase=$(extract_string_field "$json" '.status.operationState.phase'); then
    return 1
  fi
  if ! operation_absent=$(field_is_null "$json" '.operation'); then
    return 1
  fi
  printf '%s|%s' "$phase" "$operation_absent"
  return 0
}

# Waits until $app has no active/queued operation: BOTH operationState.phase is
# terminal AND .operation is null. Force-terminates and re-verifies at bounded
# deadlines. Never returns 0 on an undetermined (hard-failure) state.
wait_for_quiescence() {
  local app="$1"
  local role="$2"
  local waited=0
  local state phase operation_absent

  log "($role) checking $app for any active or queued operation (timeout ${op_wait_timeout_seconds}s, poll ${op_poll_seconds}s)"
  while :; do
    if ! state=$(get_operation_state "$app"); then
      log "ERROR: ($role) could not determine $app's operation state; refusing to proceed"
      return 1
    fi
    phase="${state%%|*}"
    operation_absent="${state##*|}"
    if is_terminal_phase "$phase" && [[ "$operation_absent" == "true" ]]; then
      log "($role) $app has no active/queued operation (phase=$phase, .operation absent)"
      return 0
    fi
    if (( waited >= op_wait_timeout_seconds )); then
      log "($role) $app still active (phase=$phase operation_absent=$operation_absent) after ${op_wait_timeout_seconds}s; force-terminating"
      if ! run_argocd "app terminate-op $app" app terminate-op "$app" >/dev/null; then
        log "ERROR: ($role) terminate-op failed for $app; refusing to proceed"
        return 1
      fi
      local term_waited=0
      while :; do
        if ! state=$(get_operation_state "$app"); then
          log "ERROR: ($role) could not verify termination for $app; refusing to proceed"
          return 1
        fi
        phase="${state%%|*}"
        operation_absent="${state##*|}"
        if is_terminal_phase "$phase" && [[ "$operation_absent" == "true" ]]; then
          log "($role) $app confirmed quiesced (phase=$phase) after terminate-op"
          return 0
        fi
        if (( term_waited >= term_wait_timeout_seconds )); then
          log "ERROR: ($role) $app still active (phase=$phase operation_absent=$operation_absent) ${term_wait_timeout_seconds}s after terminate-op; refusing to suspend an app with an unconfirmed operation"
          return 1
        fi
        sleep "$op_poll_seconds"
        term_waited=$((term_waited + op_poll_seconds))
      done
    fi
    sleep "$op_poll_seconds"
    waited=$((waited + op_poll_seconds))
  done
}

suspend_and_verify() {
  local app="$1"
  local role="$2"

  if ! $execute; then
    log "DRY-RUN: ($role) argocd app set $app --sync-policy none --context $argocd_context   # disable automation FIRST, closing the new-operation race"
    log "DRY-RUN: ($role) argocd app get $app --context $argocd_context -o json | jq -r '.status.operationState.phase, .operation'"
    log "DRY-RUN: ($role) if active/queued: poll up to ${op_wait_timeout_seconds}s, else terminate-op then verify clear within ${term_wait_timeout_seconds}s"
    log "DRY-RUN: ($role) verify within ${verify_timeout_seconds}s from a fresh, shape-validated query: automated is null AND phase is terminal AND .operation is null"
    return 0
  fi

  # Disable automation BEFORE waiting for/terminating any operation: this closes
  # the race where self-heal could start a NEW operation between "no operation
  # found" and "automation disabled." Disabling first cannot itself stop an
  # operation already in flight — that is what wait_for_quiescence is for.
  log "($role) disabling sync policy on $app (before checking for in-flight/queued operations)"
  if ! run_argocd "app set $app --sync-policy none" app set "$app" --sync-policy none >/dev/null; then
    log "ERROR: ($role) could not disable sync policy on $app"
    return 1
  fi

  if ! wait_for_quiescence "$app" "$role"; then
    return 1
  fi

  local vwaited=0
  while :; do
    local json automated_absent operation_absent phase
    if ! json=$(run_argocd "app get $app (verify)" app get "$app" -o json); then
      log "ERROR: ($role) verification query failed for $app"
      return 1
    fi
    if ! validate_application_shape "$json" "$app"; then
      log "ERROR: ($role) verification response for $app is not valid Application-shaped JSON; refusing to trust it"
      return 1
    fi
    if ! automated_absent=$(field_is_null "$json" '.spec.syncPolicy.automated'); then
      log "ERROR: ($role) could not determine syncPolicy.automated for $app during verification"
      return 1
    fi
    if ! operation_absent=$(field_is_null "$json" '.operation'); then
      log "ERROR: ($role) could not determine .operation for $app during verification"
      return 1
    fi
    if ! phase=$(extract_string_field "$json" '.status.operationState.phase'); then
      log "ERROR: ($role) could not determine operationState.phase for $app during verification"
      return 1
    fi
    if [[ "$automated_absent" == "true" && "$operation_absent" == "true" ]] && is_terminal_phase "$phase"; then
      log "($role) $app verified suspended (automation off, no active/queued operation, phase=$phase)"
      return 0
    fi
    if (( vwaited >= verify_timeout_seconds )); then
      log "ERROR: ($role) $app not fully quiesced after ${verify_timeout_seconds}s (automated_absent=$automated_absent operation_absent=$operation_absent phase=$phase); not suspended"
      return 1
    fi
    sleep "$op_poll_seconds"
    vwaited=$((vwaited + op_poll_seconds))
  done
}

log "context=$context argocd_context=$argocd_context root_app=$root_app child_apps=${child_apps[*]} execute=$execute"

if ! suspend_and_verify "$root_app" "root"; then
  log "ERROR: root suspension failed or is unverified; refusing to touch any child (a live root could re-enable one)"
  exit 1
fi

fail=0
for child in "${child_apps[@]}"; do
  if ! suspend_and_verify "$child" "child"; then
    fail=1
  fi
done

if [[ "$fail" -ne 0 ]]; then
  log "ERROR: one or more child Applications could not be verified suspended. See errors above."
  exit 1
fi

log "Root and all named child Applications suspended and verified. Progressive-delivery quiesce and resource teardown are separate, later steps."
exit 0
