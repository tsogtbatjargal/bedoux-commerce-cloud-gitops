#!/usr/bin/env bash
# Local, no-cluster regression tests for scripts/gitops-mvp-verify.sh's evidence
# checks, using a mock kubectl on an isolated PATH. Reproduces the exact defects
# from Codex's GO-MVP review (docs/PROGRESS.md session log
# 2026-09-09T20:27:22-06:00, DEF-013): stale Synced/Healthy status from a
# PREVIOUS operation was accepted as proof the CURRENT trigger succeeded; a
# missing migration Job did not fail the script; ordering violations only
# warned; web's ordering was never checked. Runs with --no-port-forward (no
# curl/port-forward dependency) so this suite exercises exactly the evidence
# logic, not the HTTP layer.

set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gitops-mvp-verify.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail_count=0
assert() {
  local desc="$1" cond="$2"
  if [[ "$cond" -eq 0 ]]; then
    printf 'PASS: %s\n' "$desc"
  else
    printf 'FAIL: %s\n' "$desc"
    fail_count=$((fail_count + 1))
  fi
}

mock_bin_dir() {
  local name="$1"
  local d="$work/$name"
  mkdir -p "$d"
  printf '%s' "$d"
}

run_with_mock() {
  local bindir="$1"
  shift
  set +e
  last_output=$(PATH="$bindir:$PATH" "$script" "$@" --no-port-forward --skip-sync 2>&1)
  last_exit=$?
  set -e
}

# Common mock kubectl body, parameterized by env vars each scenario sets:
#   MOCK_MIGRATE_JOB_MISSING=1        job get returns not-found
#   MOCK_MIGRATE_JOB_NOT_SUCCEEDED=1  job exists but succeeded=0 / no completionTime
#   MOCK_SYNC_REVISION_MISMATCH=1     status.sync.revision != requested targetRevision
#   MOCK_ORDERING_VIOLATION=web|api   that pod's creationTimestamp is BEFORE migrate completion
#   MOCK_ROLLOUT_FAILS=1              `rollout status` exits non-zero
#   MOCK_OUTOFSYNC_RETAINED_JOB_ONLY=1  sync.status=OutOfSync, but the only non-Synced
#                                        resource is a retained prior-release Job
#   MOCK_OUTOFSYNC_OTHER_DRIFT=1        sync.status=OutOfSync with a non-Job resource
#                                        (a Deployment) also OutOfSync — must still fail
write_mock_kubectl() {
  local dir="$1"
  cat >"$dir/kubectl" <<'MOCKEOF'
#!/usr/bin/env bash
args="$*"
requested_rev="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
image_tag="mvp-cafef00dbabe"
migrate_done="2026-01-01T00:00:00Z"
api_pod_created="2026-01-01T00:00:05Z"
web_pod_created="2026-01-01T00:00:05Z"

if [[ "${MOCK_ORDERING_VIOLATION:-}" == "api" ]]; then
  api_pod_created="2025-12-31T23:59:00Z"
fi
if [[ "${MOCK_ORDERING_VIOLATION:-}" == "web" ]]; then
  web_pod_created="2025-12-31T23:59:00Z"
fi

sync_revision="$requested_rev"
if [[ "${MOCK_SYNC_REVISION_MISMATCH:-}" == "1" ]]; then
  sync_revision="0000000000000000000000000000000000000000"
fi

case "$args" in
  *"get application bedoux-demo"*"jsonpath={.spec.source.targetRevision}"*)
    echo "$requested_rev" ;;
  *"get application bedoux-demo"*"jsonpath={.spec.source.helm.valuesObject.api.image.tag}"*)
    echo "$image_tag" ;;
  *"get application bedoux-demo"*"jsonpath={.status.operationState.startedAt}"*)
    echo "2026-01-01T00:00:10Z" ;;
  *"get application bedoux-demo"*"range .status.resources"*)
    if [[ "${MOCK_OUTOFSYNC_RETAINED_JOB_ONLY:-}" == "1" ]]; then
      printf 'Deployment|api|Synced\nJob|bedoux-migrate-gitops-mvp-oldtag|OutOfSync\nJob|%s|Synced\n' "bedoux-migrate-gitops-${image_tag,,}"
    elif [[ "${MOCK_OUTOFSYNC_OTHER_DRIFT:-}" == "1" ]]; then
      printf 'Deployment|api|OutOfSync\nJob|%s|Synced\n' "bedoux-migrate-gitops-${image_tag,,}"
    else
      printf 'Deployment|api|Synced\nJob|%s|Synced\n' "bedoux-migrate-gitops-${image_tag,,}"
    fi
    ;;
  *"get application bedoux-demo"*"jsonpath={.status.sync.status}"*)
    if [[ "${MOCK_OUTOFSYNC_RETAINED_JOB_ONLY:-}" == "1" || "${MOCK_OUTOFSYNC_OTHER_DRIFT:-}" == "1" ]]; then
      echo "OutOfSync"
    else
      echo "Synced"
    fi ;;
  *"get application bedoux-demo"*"jsonpath={.status.health.status}"*)
    echo "Healthy" ;;
  *"get application bedoux-demo"*"jsonpath={.status.operationState.phase}"*)
    echo "Succeeded" ;;
  *"get application bedoux-demo"*"jsonpath={.status.sync.revision}"*)
    echo "$sync_revision" ;;
  *"get application bedoux-demo"*)
    exit 0 ;;
  *"get job "*)
    if [[ "${MOCK_MIGRATE_JOB_MISSING:-}" == "1" ]]; then
      echo "Error from server (NotFound): jobs.batch not found" >&2
      exit 1
    fi
    case "$args" in
      *"jsonpath={.status.succeeded}"*)
        if [[ "${MOCK_MIGRATE_JOB_NOT_SUCCEEDED:-}" == "1" ]]; then echo ""; else echo "1"; fi ;;
      *"jsonpath={.status.completionTime}"*)
        if [[ "${MOCK_MIGRATE_JOB_NOT_SUCCEEDED:-}" == "1" ]]; then echo ""; else echo "$migrate_done"; fi ;;
      *) exit 0 ;;
    esac
    ;;
  *"rollout status deployment/"*)
    if [[ "${MOCK_ROLLOUT_FAILS:-}" == "1" ]]; then
      echo "error: deployment rollout exceeded its progress deadline" >&2
      exit 1
    fi
    exit 0 ;;
  *"get pods -l app=api"*"field-selector=status.phase=Running"*)
    echo "$api_pod_created" ;;
  *"get pods -l app=web"*"field-selector=status.phase=Running"*)
    echo "$web_pod_created" ;;
  *"get deploy,job,pods,svc"*)
    echo "mock: resource listing" ;;
  *)
    echo "mock kubectl: unhandled args: $args" >&2
    exit 1
    ;;
esac
MOCKEOF
  chmod +x "$dir/kubectl"
}

### Positive control: everything genuinely correct -> exit 0. ###
bindir1=$(mock_bin_dir scenario1)
write_mock_kubectl "$bindir1"
run_with_mock "$bindir1"
assert "positive control (all evidence genuinely present/consistent): exits 0" "$([[ "$last_exit" -eq 0 ]]; echo $?)"
assert "positive control: reports ALL checks passed" "$([[ "$last_output" == *"ALL NON-HTTP CHECKS PASSED"* ]]; echo $?)"

### DEF-013 repro 1: missing migration Job must fail, not silently pass. ###
bindir2=$(mock_bin_dir scenario2)
write_mock_kubectl "$bindir2"
MOCK_MIGRATE_JOB_MISSING=1 run_with_mock "$bindir2"
assert "REPRO CLOSED: missing migration Job -> exits non-zero (was silently exit 0)" "$([[ "$last_exit" -ne 0 ]]; echo $?)"
assert "missing migration Job: error names it" "$([[ "$last_output" == *"does not exist"* ]]; echo $?)"

### Migration Job exists but never actually Succeeded. ###
bindir3=$(mock_bin_dir scenario3)
write_mock_kubectl "$bindir3"
MOCK_MIGRATE_JOB_NOT_SUCCEEDED=1 run_with_mock "$bindir3"
assert "migration Job exists but not Succeeded -> exits non-zero" "$([[ "$last_exit" -ne 0 ]]; echo $?)"

### DEF-013 repro 2: status.sync.revision not matching the requested revision ###
### (stale evidence from a different sync) must fail. ###
bindir4=$(mock_bin_dir scenario4)
write_mock_kubectl "$bindir4"
MOCK_SYNC_REVISION_MISMATCH=1 run_with_mock "$bindir4"
assert "REPRO CLOSED: sync.revision mismatch (stale evidence) -> exits non-zero (was accepted as success)" "$([[ "$last_exit" -ne 0 ]]; echo $?)"
assert "sync.revision mismatch: error names it stale evidence" "$([[ "$last_output" == *"stale evidence"* ]]; echo $?)"

### DEF-013 repro 3: ordering violation for API must fail (already worked before). ###
bindir5=$(mock_bin_dir scenario5)
write_mock_kubectl "$bindir5"
MOCK_ORDERING_VIOLATION=api run_with_mock "$bindir5"
assert "api ordering violation -> exits non-zero" "$([[ "$last_exit" -ne 0 ]]; echo $?)"
assert "api ordering violation: error names it an ORDERING VIOLATION" "$([[ "$last_output" == *"ORDERING VIOLATION"* ]]; echo $?)"

### DEF-013 repro 4 (the one the header specifically calls out as newly fixed): ###
### ordering violation for WEB must ALSO fail — previously never checked at all. ###
bindir6=$(mock_bin_dir scenario6)
write_mock_kubectl "$bindir6"
MOCK_ORDERING_VIOLATION=web run_with_mock "$bindir6"
assert "REPRO CLOSED: web ordering violation -> exits non-zero (web was never checked before)" "$([[ "$last_exit" -ne 0 ]]; echo $?)"

### A rollout that never completes must fail, not be masked by a stale ###
### Application-level Healthy status. ###
bindir7=$(mock_bin_dir scenario7)
write_mock_kubectl "$bindir7"
MOCK_ROLLOUT_FAILS=1 run_with_mock "$bindir7"
assert "incomplete rollout -> exits non-zero" "$([[ "$last_exit" -ne 0 ]]; echo $?)"

### GO-MVP-U1 live finding (docs/PROGRESS.md session log, 2026-09-10): old ###
### per-tag migration Jobs are deliberately retained/never pruned, so a real ###
### image update leaves status.sync.status permanently OutOfSync even once the ###
### current release is genuinely Healthy/Synced-in-substance. OutOfSync must be ###
### tolerated ONLY when every non-Synced resource is a retained prior-release Job. ###
bindir9=$(mock_bin_dir scenario9)
write_mock_kubectl "$bindir9"
MOCK_OUTOFSYNC_RETAINED_JOB_ONLY=1 run_with_mock "$bindir9"
assert "OutOfSync solely due to a retained prior-release Job -> still exits 0" "$([[ "$last_exit" -eq 0 ]]; echo $?)"

### The same OutOfSync status must NOT be tolerated when a non-Job resource (or ###
### the CURRENT release's own Job) is what's actually drifted — that is real ###
### evidence something is wrong, not an artifact of the retained-Job design. ###
bindir10=$(mock_bin_dir scenario10)
write_mock_kubectl "$bindir10"
MOCK_OUTOFSYNC_OTHER_DRIFT=1 run_with_mock "$bindir10"
assert "OutOfSync from a genuinely drifted (non-Job) resource -> exits non-zero" "$([[ "$last_exit" -ne 0 ]]; echo $?)"

### Codex's GO-MVP follow-up review (docs/PROGRESS.md session log ###
### 2026-09-09T20:55:51-06:00, DEF-013): "all 11 tests use --skip-sync; add ###
### actual-trigger transition tests." These run WITHOUT --skip-sync, exercising ###
### the real `patch ... operation.sync` trigger path and a mocked operationState ###
### that genuinely TRANSITIONS across polls (stale-prior-operation for the first ###
### two polls, then a genuinely new operation from the third poll on) — proving ###
### the wait loop keeps polling through the transient "not current yet" window ###
### instead of fast-failing on it (the exact bug the same review reproduced: a ###
### false REFUSE in zero seconds despite the stated 300s wait). ###
run_with_trigger_mock() {
  local bindir="$1"
  shift
  set +e
  last_output=$(PATH="$bindir:$PATH" "$script" "$@" --no-port-forward 2>&1)
  last_exit=$?
  set -e
}

# MOCK_STALE_POLLS=N: the first N polls after the trigger still report the OLD
# (prior) operation's startedAt/state; poll N+1 onward reports a genuinely NEW
# operation. MOCK_NEVER_TRANSITIONS=1: startedAt never changes at all (models a
# trigger whose operation genuinely never advances within the deadline).
write_mock_kubectl_trigger() {
  local dir="$1"
  local stale_polls="${2:-0}"
  local never_transitions="${3:-0}"
  local counter_file="$dir/.poll_count"
  : >"$counter_file"
  cat >"$dir/kubectl" <<MOCKEOF
#!/usr/bin/env bash
args="\$*"
requested_rev="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
image_tag="mvp-cafef00dbabe"
migrate_done="2026-01-01T00:00:00Z"
prior_started_at="2025-12-31T23:00:00Z"
new_started_at="2026-01-01T00:10:00Z"
counter_file="$counter_file"

case "\$args" in
  *"get application bedoux-demo"*"jsonpath={.spec.source.targetRevision}"*) echo "\$requested_rev"; exit 0 ;;
  *"get application bedoux-demo"*"jsonpath={.spec.source.helm.valuesObject.api.image.tag}"*) echo "\$image_tag"; exit 0 ;;
  *"get application bedoux-demo"*"jsonpath={.status.sync.status}"*) polls=\$(cat "\$counter_file" 2>/dev/null | wc -l); echo "\$((polls + 1))" >> "\$counter_file"; echo "Synced"; exit 0 ;;
  *"get application bedoux-demo"*"jsonpath={.status.health.status}"*) echo "Healthy"; exit 0 ;;
  *"get application bedoux-demo"*"jsonpath={.status.operationState.phase}"*) echo "Succeeded"; exit 0 ;;
  *"get application bedoux-demo"*"jsonpath={.status.operationState.startedAt}"*)
    polls=\$(cat "\$counter_file" 2>/dev/null | wc -l)
    if [[ "$never_transitions" == "1" ]]; then
      echo "\$prior_started_at"
    elif [[ "\$polls" -gt "$stale_polls" ]]; then
      echo "\$new_started_at"
    else
      echo "\$prior_started_at"
    fi
    exit 0 ;;
  *"get application bedoux-demo"*"jsonpath={.status.sync.revision}"*) echo "\$requested_rev"; exit 0 ;;
  *"patch application bedoux-demo"*) exit 0 ;;
  *"get application bedoux-demo"*) exit 0 ;;
  *"get job "*)
    case "\$args" in
      *"jsonpath={.status.succeeded}"*) echo "1" ;;
      *"jsonpath={.status.completionTime}"*) echo "\$migrate_done" ;;
      *) exit 0 ;;
    esac ;;
  *"rollout status deployment/"*) exit 0 ;;
  *"get pods -l app=api"*"field-selector=status.phase=Running"*) echo "\$migrate_done" ;;
  *"get pods -l app=web"*"field-selector=status.phase=Running"*) echo "\$migrate_done" ;;
  *"get deploy,job,pods,svc"*) echo "mock: resource listing" ;;
  *) echo "mock kubectl: unhandled args: \$args" >&2; exit 1 ;;
esac
MOCKEOF
  chmod +x "$dir/kubectl"
}

### Positive: the operation is stale for the first 2 polls (10s of real wait, ###
### two 5s sleeps) then genuinely transitions — must NOT fast-fail during the ###
### stale window, and must succeed once the new operation is actually observed. ###
bindir8=$(mock_bin_dir scenario8)
write_mock_kubectl_trigger "$bindir8" 2
run_with_trigger_mock "$bindir8"
assert "REPRO CLOSED: real trigger, operation transitions from stale to current after a couple polls -> exits 0 (previously: false REFUSE in zero seconds)" \
  "$([[ "$last_exit" -eq 0 ]]; echo $?)"
assert "real trigger: actually issued the patch/sync trigger (not --skip-sync)" \
  "$([[ "$last_output" == *"triggering manual sync"* ]]; echo $?)"
assert "real trigger: waited through at least one stale-operation poll before succeeding" \
  "$([[ "$(grep -c 'sync=Synced health=Healthy op_phase=Succeeded' <<<"$last_output")" -ge 2 ]]; echo $?)"

echo
if [[ "$fail_count" -eq 0 ]]; then
  echo "ALL PASS (0 failures)"
  exit 0
else
  echo "$fail_count assertion(s) FAILED"
  exit 1
fi
