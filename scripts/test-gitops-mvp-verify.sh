#!/usr/bin/env bash
# Local, no-cluster regression tests for scripts/gitops-mvp-verify.sh's evidence
# checks, using a mock kubectl on an isolated PATH. Reproduces the exact defects
# from Codex's GO-MVP review (docs/PROGRESS.md session log
# 2026-09-09T20:27:22-06:00, DEF-013): stale Synced/Healthy status from a
# PREVIOUS operation was accepted as proof the CURRENT trigger succeeded; a
# missing migration Job did not fail the script; ordering violations only
# warned; web's ordering was never checked. Also covers Codex's GO-MVP-U1
# review (docs/PROGRESS.md session log 2026-09-10T17:24:50-06:00): a failed/
# empty/malformed resource listing was silently tolerated; any non-current Job
# was excused by name inequality alone, not positive identification; Degraded
# health was excused purely by "all drift is retained Jobs," never checking the
# current release's own resources directly; and ordering picked one pod per
# label instead of verifying every current-rollout replica and explicitly
# handling a workload the release left unchanged. Runs with --no-port-forward
# (no curl/port-forward dependency) so this suite exercises exactly the
# evidence logic, not the HTTP layer. Scenarios that legitimately never reach
# an acceptable state use GITOPS_MVP_VERIFY_WAIT_SECONDS/_POLL_SECONDS to avoid
# a real 300s wait per negative case — a test-only override, unset (default
# 300s/5s) for every other scenario and for real cluster use.

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
  last_output=$(PATH="$bindir:$PATH" GITOPS_MVP_VERIFY_WAIT_SECONDS=1 GITOPS_MVP_VERIFY_POLL_SECONDS=1 \
    "$script" "$@" --no-port-forward --skip-sync 2>&1)
  last_exit=$?
  set -e
}

# Common mock kubectl body, parameterized by env vars each scenario sets. Fixed
# identities: requested_rev/image_tag/migrate_job as below; retained_job is a
# terminal (Succeeded), positively-named prior-release Job; unrelated_job does
# NOT match the migration-Job naming convention.
#
#   MOCK_MIGRATE_JOB_MISSING=1          current job get returns not-found
#   MOCK_MIGRATE_JOB_NOT_SUCCEEDED=1    current job exists but succeeded=0
#   MOCK_SYNC_REVISION_MISMATCH=1       status.sync.revision != requested targetRevision
#   MOCK_ORDERING_VIOLATION=web|api     that label's pod predates migrate completion
#                                       (its ReplicaSet is still "changed" i.e. new)
#   MOCK_ROLLOUT_FAILS=1                `rollout status` exits non-zero
#   MOCK_OUTOFSYNC_RETAINED_JOB_ONLY=1  sync=OutOfSync, health=Healthy; only
#                                       drift is the terminal retained_job
#   MOCK_OUTOFSYNC_OTHER_DRIFT=1        sync=OutOfSync with a Deployment also
#                                       OutOfSync — must still fail
#   MOCK_RESOURCES_QUERY_FAILS=1        the resources range query itself fails
#   MOCK_RESOURCES_EMPTY=1              the resources range query returns empty
#   MOCK_RESOURCES_MALFORMED=1          a resource line has the wrong field count
#   MOCK_UNRELATED_JOB_OUTOFSYNC=1      an OutOfSync Job NOT matching the
#                                       migration-Job naming convention
#   MOCK_RETAINED_JOB_NOT_TERMINAL=1    retained_job matches by name but its own
#                                       live status is still Active (not terminal)
#   MOCK_DEGRADED_RETAINED_HEALTHY=1    health=Degraded (retained_job Failed),
#                                       but the CURRENT release's own resources
#                                       are independently confirmed healthy
#   MOCK_DEGRADED_CURRENT_UNHEALTHY=1   health=Degraded (retained_job Failed),
#                                       AND the current release's own api
#                                       Deployment is NOT available — must fail
#   MOCK_UNCHANGED_WORKLOAD=web|api     that label's current ReplicaSet predates
#                                       this migration (release did not touch
#                                       it) — must NOT be flagged as a violation
#   MOCK_MULTI_REPLICA_VIOLATION=web|api  two current-rollout replicas, one of
#                                       which predates migrate completion
write_mock_kubectl() {
  local dir="$1"
  cat >"$dir/kubectl" <<'MOCKEOF'
#!/usr/bin/env bash
args="$*"
requested_rev="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
image_tag="mvp-cafef00dbabe"
migrate_job="bedoux-migrate-gitops-mvp-cafef00dbabe"
retained_job="bedoux-migrate-gitops-mvp-oldtag"
unrelated_job="some-other-job"
migrate_done="2026-01-01T00:00:00Z"
changed_ts="2026-01-01T00:00:05Z"
unchanged_ts="2025-12-31T00:00:00Z"

api_rs_created="$changed_ts"
web_rs_created="$changed_ts"
api_pod_created="$changed_ts"
web_pod_created="$changed_ts"
api_pod2_created="$changed_ts"
web_pod2_created="$changed_ts"
api_replicas=1
web_replicas=1

if [[ "${MOCK_ORDERING_VIOLATION:-}" == "api" ]]; then
  api_pod_created="2025-12-31T23:59:00Z"
fi
if [[ "${MOCK_ORDERING_VIOLATION:-}" == "web" ]]; then
  web_pod_created="2025-12-31T23:59:00Z"
fi
if [[ "${MOCK_UNCHANGED_WORKLOAD:-}" == "api" ]]; then
  api_rs_created="$unchanged_ts"
  api_pod_created="$unchanged_ts"
fi
if [[ "${MOCK_UNCHANGED_WORKLOAD:-}" == "web" ]]; then
  web_rs_created="$unchanged_ts"
  web_pod_created="$unchanged_ts"
fi
if [[ "${MOCK_MULTI_REPLICA_VIOLATION:-}" == "api" ]]; then
  api_replicas=2
  api_pod2_created="2025-12-31T23:59:00Z"
fi
if [[ "${MOCK_MULTI_REPLICA_VIOLATION:-}" == "web" ]]; then
  web_replicas=2
  web_pod2_created="2025-12-31T23:59:00Z"
fi

sync_revision="$requested_rev"
if [[ "${MOCK_SYNC_REVISION_MISMATCH:-}" == "1" ]]; then
  sync_revision="0000000000000000000000000000000000000000"
fi

sync_status="Synced"
health_status="Healthy"
if [[ "${MOCK_OUTOFSYNC_RETAINED_JOB_ONLY:-}" == "1" || "${MOCK_OUTOFSYNC_OTHER_DRIFT:-}" == "1" \
      || "${MOCK_RESOURCES_QUERY_FAILS:-}" == "1" || "${MOCK_RESOURCES_EMPTY:-}" == "1" \
      || "${MOCK_RESOURCES_MALFORMED:-}" == "1" || "${MOCK_UNRELATED_JOB_OUTOFSYNC:-}" == "1" \
      || "${MOCK_RETAINED_JOB_NOT_TERMINAL:-}" == "1" ]]; then
  sync_status="OutOfSync"
fi
if [[ "${MOCK_DEGRADED_RETAINED_HEALTHY:-}" == "1" || "${MOCK_DEGRADED_CURRENT_UNHEALTHY:-}" == "1" ]]; then
  sync_status="OutOfSync"
  health_status="Degraded"
fi

case "$args" in
  *"get application bedoux-demo"*"jsonpath={.spec.source.targetRevision}"*)
    echo "$requested_rev" ;;
  *"get application bedoux-demo"*"jsonpath={.spec.source.helm.valuesObject.api.image.tag}"*)
    echo "$image_tag" ;;
  *"get application bedoux-demo"*"jsonpath={.status.operationState.startedAt}"*)
    echo "2026-01-01T00:00:10Z" ;;
  *"get application bedoux-demo"*"range .status.resources"*)
    if [[ "${MOCK_RESOURCES_QUERY_FAILS:-}" == "1" ]]; then
      echo "Error from server: etcdserver: request timed out" >&2
      exit 1
    fi
    if [[ "${MOCK_RESOURCES_EMPTY:-}" == "1" ]]; then
      exit 0
    fi
    if [[ "${MOCK_RESOURCES_MALFORMED:-}" == "1" ]]; then
      printf 'Deployment|apps|api|Synced\nJob|batch|%s\n' "$migrate_job"
      exit 0
    fi
    if [[ "${MOCK_UNRELATED_JOB_OUTOFSYNC:-}" == "1" ]]; then
      printf 'Deployment|apps|api|Synced\nJob|batch|%s|OutOfSync\nJob|batch|%s|Synced\n' "$unrelated_job" "$migrate_job"
      exit 0
    fi
    if [[ "${MOCK_RETAINED_JOB_NOT_TERMINAL:-}" == "1" ]]; then
      printf 'Deployment|apps|api|Synced\nJob|batch|%s|OutOfSync\nJob|batch|%s|Synced\n' "$retained_job" "$migrate_job"
      exit 0
    fi
    if [[ "${MOCK_OUTOFSYNC_RETAINED_JOB_ONLY:-}" == "1" || "${MOCK_DEGRADED_RETAINED_HEALTHY:-}" == "1" \
          || "${MOCK_DEGRADED_CURRENT_UNHEALTHY:-}" == "1" ]]; then
      printf 'Deployment|apps|api|Synced\nJob|batch|%s|OutOfSync\nJob|batch|%s|Synced\n' "$retained_job" "$migrate_job"
      exit 0
    fi
    if [[ "${MOCK_OUTOFSYNC_OTHER_DRIFT:-}" == "1" ]]; then
      printf 'Deployment|apps|api|OutOfSync\nJob|batch|%s|Synced\n' "$migrate_job"
      exit 0
    fi
    printf 'Deployment|apps|api|Synced\nJob|batch|%s|Synced\n' "$migrate_job"
    exit 0
    ;;
  *"get application bedoux-demo"*"jsonpath={.status.sync.status}"*)
    echo "$sync_status" ;;
  *"get application bedoux-demo"*"jsonpath={.status.health.status}"*)
    echo "$health_status" ;;
  *"get application bedoux-demo"*"jsonpath={.status.operationState.phase}"*)
    echo "Succeeded" ;;
  *"get application bedoux-demo"*"jsonpath={.status.sync.revision}"*)
    echo "$sync_revision" ;;
  *"get application bedoux-demo"*)
    exit 0 ;;
  *"get job $retained_job "*"jsonpath={.status.succeeded}"*)
    if [[ "${MOCK_RETAINED_JOB_NOT_TERMINAL:-}" == "1" ]]; then echo "0"; else echo "1"; fi ;;
  *"get job $retained_job "*"jsonpath={.status.failed}"*)
    if [[ "${MOCK_DEGRADED_RETAINED_HEALTHY:-}" == "1" || "${MOCK_DEGRADED_CURRENT_UNHEALTHY:-}" == "1" ]]; then
      echo "1"
    else
      echo "0"
    fi ;;
  *"get job $retained_job "*"jsonpath={.status.active}"*)
    if [[ "${MOCK_RETAINED_JOB_NOT_TERMINAL:-}" == "1" ]]; then echo "1"; else echo "0"; fi ;;
  *"get job $migrate_job"*)
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
  *"get deployment api "*"jsonpath={.status.availableReplicas}"*)
    if [[ "${MOCK_DEGRADED_CURRENT_UNHEALTHY:-}" == "1" ]]; then echo "0"; else echo "1"; fi ;;
  *"get deployment web "*"jsonpath={.status.availableReplicas}"*)
    echo "1" ;;
  *"get deployment postgres "*"jsonpath={.status.availableReplicas}"*)
    echo "1" ;;
  *"get deployment api "*"jsonpath={.spec.replicas}"*)
    echo "$api_replicas" ;;
  *"get deployment web "*"jsonpath={.spec.replicas}"*)
    echo "$web_replicas" ;;
  *"get deployment postgres "*"jsonpath={.spec.replicas}"*)
    echo "1" ;;
  *"rollout status deployment/"*)
    if [[ "${MOCK_ROLLOUT_FAILS:-}" == "1" ]]; then
      echo "error: deployment rollout exceeded its progress deadline" >&2
      exit 1
    fi
    exit 0 ;;
  *"get rs -l app=api "*)
    printf '%s|api-rs1|apihash\n' "$api_rs_created" ;;
  *"get rs -l app=web "*)
    printf '%s|web-rs1|webhash\n' "$web_rs_created" ;;
  *"get pods -l app=api,pod-template-hash=apihash"*"field-selector=status.phase=Running"*)
    printf '%s|api-pod1\n' "$api_pod_created"
    if [[ "$api_replicas" -ge 2 ]]; then printf '%s|api-pod2\n' "$api_pod2_created"; fi ;;
  *"get pods -l app=web,pod-template-hash=webhash"*"field-selector=status.phase=Running"*)
    printf '%s|web-pod1\n' "$web_pod_created"
    if [[ "$web_replicas" -ge 2 ]]; then printf '%s|web-pod2\n' "$web_pod2_created"; fi ;;
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
assert "OutOfSync solely due to a retained, terminal, positively-identified prior-release Job -> still exits 0" \
  "$([[ "$last_exit" -eq 0 ]]; echo $?)"

### The same OutOfSync status must NOT be tolerated when a non-Job resource (or ###
### the CURRENT release's own Job) is what's actually drifted — that is real ###
### evidence something is wrong, not an artifact of the retained-Job design. ###
bindir10=$(mock_bin_dir scenario10)
write_mock_kubectl "$bindir10"
MOCK_OUTOFSYNC_OTHER_DRIFT=1 run_with_mock "$bindir10"
assert "OutOfSync from a genuinely drifted (non-Job) resource -> exits non-zero" "$([[ "$last_exit" -ne 0 ]]; echo $?)"

### Codex's GO-MVP-U1 review (docs/PROGRESS.md session log 2026-09-10T17:24:50-06:00): ###
### finding 1 — a failed, empty, or malformed resource listing must be REJECTED, ###
### never silently treated as "nothing is wrong" (the `|| true` bug). ###
bindir11=$(mock_bin_dir scenario11)
write_mock_kubectl "$bindir11"
MOCK_RESOURCES_QUERY_FAILS=1 run_with_mock "$bindir11"
assert "REPRO CLOSED: failed resource-list query -> exits non-zero (was silently tolerated)" "$([[ "$last_exit" -ne 0 ]]; echo $?)"

bindir12=$(mock_bin_dir scenario12)
write_mock_kubectl "$bindir12"
MOCK_RESOURCES_EMPTY=1 run_with_mock "$bindir12"
assert "REPRO CLOSED: empty resource-list query -> exits non-zero (was silently tolerated)" "$([[ "$last_exit" -ne 0 ]]; echo $?)"

bindir13=$(mock_bin_dir scenario13)
write_mock_kubectl "$bindir13"
MOCK_RESOURCES_MALFORMED=1 run_with_mock "$bindir13"
assert "REPRO CLOSED: malformed resource-list line -> exits non-zero (was silently tolerated)" "$([[ "$last_exit" -ne 0 ]]; echo $?)"

### Finding 2 — positively identify retained migration Jobs by naming ###
### convention; an unrelated Job (or one that ISN'T actually terminal despite ###
### matching the naming convention) must NOT qualify as an excuse. ###
bindir14=$(mock_bin_dir scenario14)
write_mock_kubectl "$bindir14"
MOCK_UNRELATED_JOB_OUTOFSYNC=1 run_with_mock "$bindir14"
assert "REPRO CLOSED: unrelated Job (not matching migration-Job naming) OutOfSync -> exits non-zero" "$([[ "$last_exit" -ne 0 ]]; echo $?)"

bindir15=$(mock_bin_dir scenario15)
write_mock_kubectl "$bindir15"
MOCK_RETAINED_JOB_NOT_TERMINAL=1 run_with_mock "$bindir15"
assert "REPRO CLOSED: retained-Job-named resource that is NOT actually terminal -> exits non-zero" "$([[ "$last_exit" -ne 0 ]]; echo $?)"

### Finding 3 — health is checked SEPARATELY from sync status: a retained Job ###
### may excuse Degraded health only when the CURRENT release's own resources ###
### are independently confirmed healthy; an unhealthy current resource is ###
### NEVER excused just because the aggregate drift is otherwise explained. ###
bindir16=$(mock_bin_dir scenario16)
write_mock_kubectl "$bindir16"
MOCK_DEGRADED_RETAINED_HEALTHY=1 run_with_mock "$bindir16"
assert "PRESERVED: Degraded health from a retained Failed Job, current release independently confirmed healthy -> still exits 0 (valid recovery)" \
  "$([[ "$last_exit" -eq 0 ]]; echo $?)"

bindir17=$(mock_bin_dir scenario17)
write_mock_kubectl "$bindir17"
MOCK_DEGRADED_CURRENT_UNHEALTHY=1 run_with_mock "$bindir17"
assert "REPRO CLOSED: Degraded health from a retained Failed Job, but the CURRENT api Deployment is not Available -> exits non-zero (never excused)" \
  "$([[ "$last_exit" -ne 0 ]]; echo $?)"

### Finding 4 — ordering identifies the current-rollout ReplicaSet and checks ###
### EVERY relevant replica; a workload the release left UNCHANGED (its current ###
### ReplicaSet predates this migration) must be reported as such, not flagged. ###
bindir18=$(mock_bin_dir scenario18)
write_mock_kubectl "$bindir18"
MOCK_UNCHANGED_WORKLOAD=web run_with_mock "$bindir18"
assert "REPRO CLOSED: web left UNCHANGED by this release -> still exits 0, not flagged as an ordering violation" \
  "$([[ "$last_exit" -eq 0 ]]; echo $?)"
assert "unchanged workload: reported explicitly as unchanged, not silently skipped" \
  "$([[ "$last_output" == *"UNCHANGED by this release"* ]]; echo $?)"

bindir19=$(mock_bin_dir scenario19)
write_mock_kubectl "$bindir19"
MOCK_MULTI_REPLICA_VIOLATION=web run_with_mock "$bindir19"
assert "REPRO CLOSED: 2-replica web rollout, one replica predates migration -> exits non-zero (single-pod check would have missed this)" \
  "$([[ "$last_exit" -ne 0 ]]; echo $?)"

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
migrate_job="bedoux-migrate-gitops-mvp-cafef00dbabe"
migrate_done="2026-01-01T00:00:00Z"
prior_started_at="2025-12-31T23:00:00Z"
new_started_at="2026-01-01T00:10:00Z"
counter_file="$counter_file"

case "\$args" in
  *"get application bedoux-demo"*"jsonpath={.spec.source.targetRevision}"*) echo "\$requested_rev"; exit 0 ;;
  *"get application bedoux-demo"*"jsonpath={.spec.source.helm.valuesObject.api.image.tag}"*) echo "\$image_tag"; exit 0 ;;
  *"get application bedoux-demo"*"range .status.resources"*)
    printf 'Deployment|apps|api|Synced\nJob|batch|%s|Synced\n' "\$migrate_job"; exit 0 ;;
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
  *"get deployment "*"jsonpath={.status.availableReplicas}"*) echo "1" ;;
  *"get deployment "*"jsonpath={.spec.replicas}"*) echo "1" ;;
  *"rollout status deployment/"*) exit 0 ;;
  *"get rs -l app=api "*) printf '%s|api-rs1|apihash\n' "\$migrate_done" ;;
  *"get rs -l app=web "*) printf '%s|web-rs1|webhash\n' "\$migrate_done" ;;
  *"get pods -l app=api,pod-template-hash=apihash"*"field-selector=status.phase=Running"*) printf '%s|api-pod1\n' "\$migrate_done" ;;
  *"get pods -l app=web,pod-template-hash=webhash"*"field-selector=status.phase=Running"*) printf '%s|web-pod1\n' "\$migrate_done" ;;
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
