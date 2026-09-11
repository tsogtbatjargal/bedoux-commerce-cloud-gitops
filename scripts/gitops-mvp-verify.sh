#!/usr/bin/env bash
# GO-MVP: trigger a manual Argo CD sync FOR THE APPLICATION'S CURRENTLY-REQUESTED
# revision/image tag, and only report success once real, current-release evidence
# confirms it — the CURRENT release's migration Job actually Succeeded, both api
# and web workloads actually advanced to Ready, migration completed before either
# was created, and both a plain and a DB-backed HTTP check return 200. No router/
# Ingress is installed in this MVP (see gitops-mvp-up.sh); this script is the only
# supported way to reach the demo from a browser.
#
# Corrected per Codex's GO-MVP review (docs/PROGRESS.md session log
# 2026-09-09T20:27:22-06:00, DEF-013): the prior version could report exit 0 with
# a stale Synced/Healthy status left over from a PREVIOUS sync (never checking
# `.status.sync.revision` against what was actually requested, nor that the
# TRIGGERED operation itself succeeded); a missing migration Job did not fail the
# script; ordering violations only logged a warning instead of failing; web's
# creation ordering was never checked despite the header claiming otherwise;
# HTTP failures were printed but never asserted; and `/health` deliberately never
# touches the database (see apps/api/app/main.py), so it cannot detect a broken
# DB credential — /products (a real, read-only, DB-backed endpoint) is now also
# checked. On an UPDATE, the prior version could also inspect the OLDEST
# retained migration Job (this MVP never auto-deletes old per-tag Jobs) instead
# of the one belonging to the currently-requested release; this version looks up
# the Job by the exact current image tag, never "the first Job found."
#
# GO-MVP-U1 live finding (docs/PROGRESS.md session log, 2026-09-10): because old
# per-tag migration Jobs are deliberately retained/never pruned, a real image
# update leaves status.sync.status permanently OutOfSync (the prior release's
# Job is an unpruned extra resource) even once the CURRENT release is genuinely
# Synced/Healthy. This script now tolerates OutOfSync ONLY when every non-Synced
# resource is a retained prior-release migration Job — any other drift still
# fails. Selects the newest RUNNING pod per label for ordering evidence, not
# `.items[0]` (not guaranteed to be the current rollout's pod during an update).
#
# Corrected per Codex's GO-MVP-U1 review (docs/PROGRESS.md session log
# 2026-09-10T17:24:50-06:00): the retained-Job tolerance above did not reject a
# failed/empty/malformed resource listing (a query error or empty output was
# silently treated as "nothing wrong" via `|| true`); it excused ANY
# non-current Job by name inequality alone, not a positively-identified
# migration Job (an unrelated Job could have qualified); it inferred CURRENT-
# release health purely from "all drift is retained Jobs," never independently
# confirming the current release's own resources are actually healthy; and its
# ordering check picked one "newest Running pod" per label, which neither
# checks every replica of a genuinely-updated workload nor recognizes a
# workload an update legitimately left UNCHANGED (whose current pods can
# predate the new migration by design, not as a violation). All four are fixed
# below, with new regression coverage for each counterexample.
#
# Corrected per Codex's follow-up GO-MVP-U1 review (docs/PROGRESS.md session
# log 2026-09-10T19:05:29-06:00): "unchanged workload" was still being proven
# by comparing a ReplicaSet's creationTimestamp to migration completion — a
# timing correlation, not evidence the pod template actually didn't change.
# Fixed to compare the ACTUAL pod-template-hash captured before this sync to
# the one active now; only a genuine hash match proves "unchanged." Job
# termination (both the current release's own migration Job and any retained
# prior-release Job) was inferred from `.status.succeeded`/`.status.failed`
# counts, which can reflect a "retry gap" (failed on an earlier attempt but
# still within backoffLimit, not actually done). Fixed to require the Job's
# own explicit `status.conditions[type=Complete|Failed,status=True]`, read via
# one validated query — a query failure is rejected the same as a Job that
# hasn't reached either condition yet.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/gitops-mvp-verify.sh [options]

Options:
  --cluster-name NAME   kind cluster name (default: bedoux-gitops-mvp).
  --namespace NAME      Demo namespace (default: bedoux-demo).
  --skip-sync           Do not trigger a new sync; only verify the Application's
                         current state against its currently-requested revision.
  --no-port-forward      Skip the HTTP checks and port-forward step (still runs
                          all other evidence checks; use this only for a status
                          peek, not as proof the demo actually works end to end).
  --help                 Show this help.

Exits non-zero, with no partial-success claim, if ANY of the following is not
confirmed from live cluster state: the Application's sync status reaches
Synced, or OutOfSync solely because of positively-identified, terminal,
retained prior-release migration Job(s) (never pruned by design — a failed/
empty/malformed resource listing, or any other OutOfSync resource, or an
unrelated Job, still fails); health reaches Healthy, or Degraded ONLY when the
same retained-Job condition holds AND the current release's own migration Job
and api/web/postgres Deployments are independently confirmed healthy via
direct queries (never inferred merely from "no other explanation was found");
`.status.sync.revision` matches its currently-requested `spec.source.
targetRevision` AND the triggered sync operation itself reports phase Succeeded
(not a stale status left over from an earlier sync); the migration Job matching
the CURRENTLY-REQUESTED image tag exists and Succeeded (a "Succeeded" here
means the Job's own explicit `status.conditions[type=Complete,status=True]`,
never inferred from a `.status.succeeded` count — which can reflect a Job
still retrying after an earlier failed attempt); both api and web Deployments'
rollouts complete; for each of api/web that this release actually updated
(proven by its current ReplicaSet's pod-template-hash differing from before
this sync was triggered, never by comparing a timestamp to migration
completion — a workload whose hash is unchanged is reported as such, not
checked as a violation), migration completed at/before EVERY one of its
current replicas; `/health`, `/` and `/products` (a real, read-only, DB-backed
endpoint — see
apps/api/app/routers/products.py) all return HTTP 200 through port-forward
(unless --no-port-forward).
EOF
}

cluster_name="bedoux-gitops-mvp"
namespace="bedoux-demo"
skip_sync=false
do_port_forward=true

while (($#)); do
  case "$1" in
    --cluster-name) cluster_name="$2"; shift 2 ;;
    --namespace) namespace="$2"; shift 2 ;;
    --skip-sync) skip_sync=true; shift ;;
    --no-port-forward) do_port_forward=false; shift ;;
    --help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

log() { printf '[gitops-mvp-verify] %s\n' "$1" >&2; }
kctl() { kubectl --context "kind-$cluster_name" "$@"; }
fail() { echo "REFUSE: $1" >&2; exit 1; }

if ! kctl -n argocd get application bedoux-demo >/dev/null 2>&1; then
  fail "Application 'bedoux-demo' not found in context kind-${cluster_name} — run scripts/gitops-mvp-up.sh first"
fi

requested_revision=$(kctl -n argocd get application bedoux-demo -o jsonpath='{.spec.source.targetRevision}')
image_tag=$(kctl -n argocd get application bedoux-demo -o jsonpath='{.spec.source.helm.valuesObject.api.image.tag}')
if [[ -z "$requested_revision" || -z "$image_tag" ]]; then
  fail "could not read spec.source.targetRevision / api.image.tag from the Application — cannot identify which release to verify"
fi
log "verifying release: targetRevision=$requested_revision image_tag=$image_tag"

### The migration Job for THIS EXACT release (image tag), never "whichever Job ###
### happens to exist" — old per-tag Jobs are deliberately retained (never ###
### auto-deleted), so on an update there can be more than one. Computed here, ###
### before the sync-wait loop, so the OutOfSync tolerance check below can use it. ###
migrate_job="bedoux-migrate-gitops-${image_tag,,}"

# GO-MVP-U1 live finding: because old per-tag migration Jobs are deliberately
# retained (never pruned — see migrate_job above), a real image-tag update
# leaves the PRIOR release's Job resource in the Application's live state but
# no longer in the desired manifest for the new targetRevision. syncPolicy: {}
# never prunes (a plain `operation: {sync: {}}` trigger, as used here, does not
# pass --prune either), so Argo's Application-level status.sync.status reports
# OutOfSync indefinitely after the first real update — even though the CURRENT
# release's own resources are all genuinely Synced. Reproduced live 2026-09-10
# (docs/PROGRESS.md GO-MVP-U1.2 session log): requiring a bare "Synced" here
# would either false-REFUSE every real update forever, or (if simply dropped)
# stop checking sync status at all. Instead: tolerate OutOfSync ONLY when every
# non-Synced resource is a Job that is NOT this release's migrate_job (i.e. a
# retained prior release's Job, the expected/documented shape) — any other
# drift (a Deployment, Service, Secret, or even THIS release's own Job showing
# OutOfSync) still fails.
#
# migrate_job_name_pattern positively identifies a migration Job BY NAMING
# CONVENTION (gitops-mvp-up.sh always names it "bedoux-migrate-gitops-<tag>"),
# not merely "any Job whose name isn't the current one" — an unrelated Job
# dropped into this namespace by something else must NOT qualify as a retained
# migration Job just because it also happens not to be $migrate_job.
migrate_job_name_pattern='^bedoux-migrate-gitops-'

# Corrected per Codex's GO-MVP-U1 review (docs/PROGRESS.md session log
# 2026-09-10T19:05:29-06:00): terminal Job state must come from the Job
# controller's own explicit `status.conditions[type=Complete|Failed,
# status="True"]` — never inferred from `.status.succeeded`/`.status.failed`
# counts. A Job can show `failed >= 1` from an EARLIER attempt while still
# genuinely retrying (backoffLimit not yet exhausted) — that is a "retry gap,"
# not termination, and treating `failed >= 1` as terminal would wrongly excuse
# a Job that has not actually finished failing yet. Reads the Job with ONE
# query; a failed/unparseable query is a separate, explicit rejection reason
# from "read fine, but no terminal condition is set yet" — both mean "do not
# confirm terminal," never silently default to a count-based guess.
#
# Echoes "Complete" or "Failed" on success with a True condition of that type;
# echoes nothing (empty) if the query succeeded but no terminal condition is
# set yet (still running/pending/retrying). Returns 1 ONLY when the query
# itself could not be read at all — callers must treat an empty-but-successful
# read as "not yet terminal," not as a query failure.
job_condition_state() {
  local ns="$1" name="$2" raw
  if ! raw=$(kctl -n "$ns" get job "$name" -o jsonpath='{range .status.conditions[?(@.status=="True")]}{.type}{"\n"}{end}' 2>&1); then
    log "could not read Job '$name' conditions ($raw) — refusing to guess its terminal state"
    return 1
  fi
  if grep -qx 'Complete' <<<"$raw"; then
    echo "Complete"
  elif grep -qx 'Failed' <<<"$raw"; then
    echo "Failed"
  fi
  return 0
}

retained_jobs_only_out_of_sync() {
  local resources_raw
  # A failed or empty query is NEVER treated as "nothing is wrong" — it means
  # we cannot positively identify anything, so the OutOfSync/Degraded state is
  # NOT explained and must not be tolerated. `|| true` on the read loop's
  # source alone previously hid exactly this (an empty stream just iterates
  # zero times and returns success) — fixed by checking the query's own
  # success and non-emptiness explicitly before ever trusting its content.
  if ! resources_raw=$(kctl -n argocd get application bedoux-demo -o jsonpath='{range .status.resources[*]}{.kind}{"|"}{.group}{"|"}{.name}{"|"}{.status}{"\n"}{end}' 2>&1); then
    log "could not read the Application's resource list ($resources_raw) — cannot positively identify retained Jobs; not tolerating"
    return 1
  fi
  if [[ -z "$resources_raw" ]]; then
    log "Application's resource list came back empty — cannot positively identify retained Jobs; not tolerating"
    return 1
  fi
  local bad=0
  local line kind group name status field_count
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    IFS='|' read -r kind group name status <<<"$line"
    field_count=$(($(grep -o '|' <<<"$line" | wc -l) + 1))
    if [[ "$field_count" -ne 4 || -z "$kind" || -z "$name" || -z "$status" ]]; then
      log "malformed resource-list line, refusing to trust it: '$line'"
      bad=1
      continue
    fi
    if [[ "$status" == "Synced" ]]; then
      continue
    fi
    if [[ "$kind" == "Job" && "$group" == "batch" && "$name" != "$migrate_job" && "$name" =~ $migrate_job_name_pattern ]]; then
      # Positively identified as a retained migration Job by naming
      # convention — but still confirm its OWN live status is genuinely
      # terminal (an explicit Complete or Failed condition, not inferred from
      # succeeded/failed counts which can reflect a retry still in progress),
      # via a direct, single, validated query against the real Job resource
      # rather than trusting the Application's cached resource-status alone.
      local j_state
      if ! j_state=$(job_condition_state "$namespace" "$name"); then
        bad=1
        continue
      fi
      if [[ "$j_state" == "Complete" || "$j_state" == "Failed" ]]; then
        log "OutOfSync resource confirmed as a terminal retained migration Job: name=$name status=$status condition=$j_state"
        continue
      fi
      log "OutOfSync Job '$name' matches the retained-migration-Job naming convention but has no terminal Complete/Failed condition yet (possibly still retrying) — not tolerating"
      bad=1
      continue
    fi
    log "OutOfSync resource is not a positively-identified retained migration Job: kind=$kind group=$group name=$name status=$status"
    bad=1
  done <<<"$resources_raw"
  return "$bad"
}

# Independent, direct confirmation that the CURRENT release's own resources
# are actually healthy — never inferred merely because "the only drift is
# retained Jobs." This is the ONLY thing allowed to justify tolerating the
# Application's aggregate health reading Degraded (a retained, unrelated
# Failed Job can drag that aggregate down even when the current release is
# fine); it must independently and positively confirm the current release
# itself, not take the absence of other explanations as proof of health.
current_release_resources_healthy() {
  local job_state
  if ! job_state=$(job_condition_state "$namespace" "$migrate_job"); then
    log "current release's migration Job '$migrate_job' conditions could not be read — current release is not confirmed healthy"
    return 1
  fi
  if [[ "$job_state" != "Complete" ]]; then
    log "current release's migration Job '$migrate_job' has no terminal Complete condition yet (observed: ${job_state:-<none>}) — current release is not confirmed healthy"
    return 1
  fi
  local dep avail desired
  for dep in api web postgres; do
    avail=$(kctl -n "$namespace" get deployment "$dep" -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)
    desired=$(kctl -n "$namespace" get deployment "$dep" -o jsonpath='{.spec.replicas}' 2>/dev/null || true)
    if [[ -z "$avail" || -z "$desired" || "$avail" -lt 1 || "$avail" -lt "$desired" ]]; then
      log "current release's Deployment '$dep' is not fully Available (available=${avail:-0} desired=${desired:-?}) — current release is not confirmed healthy"
      return 1
    fi
  done
  return 0
}

# Prints "<creationTimestamp>|<name>|<pod-template-hash>" for the ReplicaSet
# this Deployment's controller currently has scaled up (spec.replicas>0), or
# nothing if none exists yet (e.g. before a first-ever deploy) or the query
# fails. Ties (an anomaly at steady state) broken by latest creationTimestamp,
# with all candidates logged for transparency rather than silently picking one.
active_rs_info() {
  local dep_label="$1" lines rs_count
  lines=$(kctl -n "$namespace" get rs -l "app=${dep_label}" \
    -o jsonpath='{range .items[?(@.spec.replicas>0)]}{.metadata.creationTimestamp}{"|"}{.metadata.name}{"|"}{.metadata.labels.pod-template-hash}{"\n"}{end}' 2>/dev/null || true)
  [[ -z "$lines" ]] && return 0
  rs_count=$(wc -l <<<"$lines")
  if [[ "$rs_count" -gt 1 ]]; then
    log "more than one active ReplicaSet found for app=${dep_label} (unexpected at steady state): $(tr '\n' ' ' <<<"$lines") — using the one with the latest creationTimestamp"
  fi
  sort <<<"$lines" | tail -1
}

prior_operation_started_at=$(kctl -n argocd get application bedoux-demo -o jsonpath='{.status.operationState.startedAt}' 2>/dev/null || true)

# Corrected per Codex's GO-MVP-U1 review (docs/PROGRESS.md session log
# 2026-09-10T19:05:29-06:00): whether a workload was UNCHANGED by this release
# must be proven from actual before/after pod-template evidence — the
# pod-template-hash Kubernetes itself computes from the Deployment's pod spec
# — not inferred from comparing a ReplicaSet's creationTimestamp to this
# release's migration completion time (a timing correlation, not proof the
# template didn't change). Captured here, before any sync is triggered, so it
# reflects genuinely PRIOR state.
prior_api_hash=$(active_rs_info api | awk -F'|' '{print $3}')
prior_web_hash=$(active_rs_info web | awk -F'|' '{print $3}')

if ! $skip_sync; then
  log "triggering manual sync (syncPolicy is {} — nothing else ever syncs this Application automatically)"
  kctl -n argocd patch application bedoux-demo --type=merge -p '{"operation":{"sync":{}}}'
fi

# GITOPS_MVP_VERIFY_WAIT_SECONDS/_POLL_SECONDS: test-only overrides (default
# 300/5, unchanged from before) so local regression tests can exercise a
# negative case that legitimately never becomes acceptable without actually
# waiting 300 real seconds. Never set these for a real cluster.
wait_seconds="${GITOPS_MVP_VERIFY_WAIT_SECONDS:-300}"
poll_seconds="${GITOPS_MVP_VERIFY_POLL_SECONDS:-5}"
log "waiting up to ${wait_seconds}s for the CURRENT operation on revision $requested_revision to reach Synced+Healthy+Succeeded"
deadline=$((SECONDS + wait_seconds))
sync_status="" health_status="" op_phase="" op_started_at="" sync_revision=""
while (( SECONDS < deadline )); do
  sync_status=$(kctl -n argocd get application bedoux-demo -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
  health_status=$(kctl -n argocd get application bedoux-demo -o jsonpath='{.status.health.status}' 2>/dev/null || true)
  op_phase=$(kctl -n argocd get application bedoux-demo -o jsonpath='{.status.operationState.phase}' 2>/dev/null || true)
  op_started_at=$(kctl -n argocd get application bedoux-demo -o jsonpath='{.status.operationState.startedAt}' 2>/dev/null || true)
  sync_revision=$(kctl -n argocd get application bedoux-demo -o jsonpath='{.status.sync.revision}' 2>/dev/null || true)
  log "sync=${sync_status:-<none>} health=${health_status:-<none>} op_phase=${op_phase:-<none>} sync_revision=${sync_revision:-<none>}"
  # A triggered sync must produce a NEW operation (different startedAt) unless
  # --skip-sync was used, so a stale, already-Succeeded operation from a PRIOR
  # run can never be mistaken for evidence this run's trigger actually happened.
  operation_is_current=true
  if ! $skip_sync && [[ -n "$prior_operation_started_at" && "$op_started_at" == "$prior_operation_started_at" ]]; then
    operation_is_current=false
  fi
  # A positively-identified, terminal, retained (non-current-release) Job
  # explains BOTH symptoms of the same root cause: a prior release's Job
  # (Succeeded or Failed) is never pruned, so it can leave the Application's
  # aggregate sync status OutOfSync (a Succeeded Job pending prune) AND/OR its
  # aggregate health Degraded (a Failed Job, live-reproduced 2026-09-10 after a
  # controlled migration-failure demo). SYNC and HEALTH are still two SEPARATE
  # decisions (Codex's GO-MVP-U1 review, 2026-09-10T17:24:50-06:00): retained
  # Jobs alone are sufficient to explain OutOfSync (a prune-pending resource is
  # exactly that, nothing more to check), but they are NEVER, by themselves,
  # sufficient to excuse Degraded health — that additionally requires
  # independently and positively confirming the CURRENT release's own
  # resources (its migration Job, api/web/postgres Deployments) are actually
  # healthy via direct queries against those resources, not inferred from "no
  # other explanation was found."
  retained_only=false
  if [[ "$sync_status" != "Synced" || "$health_status" != "Healthy" ]]; then
    retained_jobs_only_out_of_sync && retained_only=true
  fi
  sync_acceptable=false
  if [[ "$sync_status" == "Synced" || ( "$sync_status" == "OutOfSync" && "$retained_only" == true ) ]]; then
    sync_acceptable=true
  fi
  health_acceptable=false
  if [[ "$health_status" == "Healthy" ]]; then
    health_acceptable=true
  elif [[ "$health_status" == "Degraded" && "$retained_only" == true ]] && current_release_resources_healthy; then
    health_acceptable=true
  fi
  if [[ "$sync_acceptable" == true && "$health_acceptable" == true && "$op_phase" == "Succeeded" \
        && "$sync_revision" == "$requested_revision" && "$operation_is_current" == true ]]; then
    break
  fi
  # Fail fast, rather than spinning for the full 300s, ONLY when we have
  # CONFIRMED we are looking at the CURRENT (this run's triggered) operation AND
  # it has reached a terminal state that will never self-correct on its own —
  # never merely because the operation isn't current yet. Right after queuing a
  # sync, the controller has not necessarily picked it up yet, so the FIRST few
  # polls legitimately still show the PREVIOUS operation's (possibly already
  # Succeeded) status — that is an expected transient, not a failure, and must
  # keep polling normally until either a genuinely new operation appears or the
  # timeout expires. Reproduced live and by Codex's GO-MVP review
  # (docs/PROGRESS.md session log 2026-09-09T20:55:51-06:00): an earlier version
  # of this fix fast-failed the instant it observed operation_is_current==false,
  # which is exactly the expected state in the first fraction of a second after
  # triggering — a false REFUSE in zero seconds despite the stated 300s wait.
  # (A separate, now-fixed bug in the same area: fast-failing the instant
  # op_phase reported Succeeded even though health was still legitimately
  # "Progressing" — pods can still be starting after a Succeeded sync operation,
  # so that alone must also keep polling normally, not fail fast.)
  if [[ "$operation_is_current" == true ]]; then
    case "$op_phase" in
      Succeeded)
        if [[ "$sync_revision" != "$requested_revision" ]]; then
          break
        fi
        ;;
      Failed|Error)
        break
        ;;
    esac
  fi
  sleep "$poll_seconds"
done
if [[ "$sync_acceptable" != true ]]; then
  fail "Application did not reach an acceptable Synced state within 300s (last observed: sync=$sync_status, and it is not explained by retained prior-release migration Job(s) alone; health=$health_status op_phase=$op_phase). Run 'kubectl --context kind-${cluster_name} -n argocd get application bedoux-demo -o yaml' for details."
fi
if [[ "$health_acceptable" != true || "$op_phase" != "Succeeded" ]]; then
  fail "Application did not reach an acceptable Healthy+Succeeded state within 300s (last observed: sync=$sync_status health=$health_status, and it is not explained by retained prior-release migration Job(s) alone; op_phase=$op_phase). Run 'kubectl --context kind-${cluster_name} -n argocd get application bedoux-demo -o yaml' for details."
fi
if [[ "$sync_revision" != "$requested_revision" ]]; then
  fail "Application reports an acceptable sync/health state, but status.sync.revision ($sync_revision) does not match the currently-requested targetRevision ($requested_revision) — this is stale evidence from a different sync, not proof this release deployed."
fi
if [[ "$operation_is_current" != true ]]; then
  fail "Application reports an acceptable Healthy+Succeeded state, but the operation's startedAt ($op_started_at) is unchanged from before this script triggered a sync ($prior_operation_started_at) — this is stale evidence from a PREVIOUS run, not proof the sync just triggered actually happened."
fi
if [[ "$sync_status" == "Synced" && "$health_status" == "Healthy" ]]; then
  log "Application is Synced+Healthy at the currently-requested revision, with the triggered operation Succeeded."
else
  log "Application is at the currently-requested revision with the triggered operation Succeeded (sync=$sync_status health=$health_status), tolerated ONLY because every non-Synced resource is a retained prior-release migration Job (Succeeded or Failed), which this MVP deliberately never prunes — not treated as a failure. The CURRENT release's own migration Job, rollouts, and ordering are still independently verified below."
fi

if ! kctl -n "$namespace" get job "$migrate_job" >/dev/null 2>&1; then
  fail "migration Job '$migrate_job' for the current release (image tag $image_tag) does not exist in namespace $namespace — cannot confirm migrations ran for this release."
fi
# Terminal state comes from the Job's own explicit Complete condition, never
# from a `.status.succeeded` count alone (Codex's GO-MVP-U1 review,
# 2026-09-10T19:05:29-06:00) — see job_condition_state's header comment.
if ! migrate_state=$(job_condition_state "$namespace" "$migrate_job"); then
  fail "could not read migration Job '$migrate_job's conditions — refusing to claim a working release."
fi
if [[ "$migrate_state" != "Complete" ]]; then
  fail "migration Job '$migrate_job' has no terminal Complete condition yet (observed: ${migrate_state:-<none>}) — refusing to claim a working release."
fi
migrate_done=$(kctl -n "$namespace" get job "$migrate_job" -o jsonpath='{.status.completionTime}' 2>/dev/null || true)
if [[ -z "$migrate_done" ]]; then
  fail "migration Job '$migrate_job' reports a Complete condition but has no completionTime — cannot verify ordering."
fi
log "migration Job '$migrate_job' Succeeded (Complete condition) at $migrate_done"

### Both api AND web rollouts must actually complete for THIS release — not just ###
### "the Application is Healthy," which can be satisfied by stale pods if a ###
### rollout is still converging at the exact moment of a status read. ###
for dep in api web; do
  if ! kctl -n "$namespace" rollout status "deployment/${dep}" --timeout=120s >/dev/null; then
    fail "deployment/${dep} did not complete its rollout for this release"
  fi
done

### Ordering evidence for BOTH api and web — a violation FAILS the script, it is ###
### no longer a soft warning (DEF-013). ###
#
# Corrected per Codex's GO-MVP-U1 review (docs/PROGRESS.md session log
# 2026-09-10T17:24:50-06:00): picking one "newest Running pod" per label
# neither identifies the CURRENT ROLLOUT positively (a ReplicaSet, not a
# single pod picked by timestamp) nor checks every replica it owns — a
# multi-replica release (e.g. GO-MVP's own web.replicas=2 scaling case) could
# have one on-time replica and one genuinely late one, and only checking the
# newest would miss the second. It also could not distinguish a workload this
# release genuinely UPDATED from one it left UNCHANGED (no new image/values
# for that workload => no new ReplicaSet => its existing, unchanged pods
# legitimately predate this migration's completion — that is not a violation,
# and must be reported as such explicitly, not silently skipped or wrongly
# flagged).
for dep_label in "api" "web"; do
  # Identify the CURRENT rollout's ReplicaSet: the one this Deployment's
  # controller actually scaled up (spec.replicas > 0).
  current_rs_line=$(active_rs_info "$dep_label")
  if [[ -z "$current_rs_line" ]]; then
    fail "no active ReplicaSet (spec.replicas>0) found for app=${dep_label} in namespace $namespace — cannot identify the current rollout to verify ordering."
  fi
  IFS='|' read -r rs_created rs_name rs_hash <<<"$current_rs_line"
  if [[ -z "$rs_created" || -z "$rs_name" ]]; then
    fail "could not parse the current ReplicaSet's identity for app=${dep_label} (line: '$current_rs_line') — cannot verify ordering."
  fi
  log "${dep_label}: current rollout is ReplicaSet '$rs_name' (created $rs_created, pod-template-hash=${rs_hash:-<none>})"

  # Proof of "unchanged" comes from comparing the ACTUAL pod-template-hash
  # captured before this sync to the one active now — not from comparing this
  # ReplicaSet's creationTimestamp to the migration's completion time (a
  # timing correlation, not evidence about the template itself; a hash match
  # means Kubernetes computed the identical pod spec both times, which a
  # timestamp comparison can never prove or disprove).
  case "$dep_label" in
    api) prior_hash="$prior_api_hash" ;;
    web) prior_hash="$prior_web_hash" ;;
  esac
  if [[ -n "$rs_hash" && "$rs_hash" == "$prior_hash" ]]; then
    log "OBSERVED: ${dep_label}'s current ReplicaSet pod-template-hash ($rs_hash) is IDENTICAL to before this sync was triggered — this workload was left UNCHANGED by this release (proven by template identity, not by comparing timestamps). Ordering is not applicable to an unchanged workload; not claiming a violation."
    continue
  fi

  # This workload WAS updated by this release: verify EVERY one of its
  # current-rollout replicas, not just one, and require the desired replica
  # count was actually found (a partially-listed set would silently under-
  # check ordering).
  selector="app=${dep_label}"
  [[ -n "$rs_hash" ]] && selector="app=${dep_label},pod-template-hash=${rs_hash}"
  pod_lines=$(kctl -n "$namespace" get pods -l "$selector" --field-selector=status.phase=Running \
    -o jsonpath='{range .items[*]}{.metadata.creationTimestamp}{"|"}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
  if [[ -z "$pod_lines" ]]; then
    fail "no Running pod found for the current ReplicaSet '$rs_name' (app=${dep_label}) — cannot confirm ordering or health for it."
  fi
  desired_replicas=$(kctl -n "$namespace" get deployment "$dep_label" -o jsonpath='{.spec.replicas}' 2>/dev/null || true)
  pod_count=$(wc -l <<<"$pod_lines")
  if [[ -n "$desired_replicas" && "$pod_count" -lt "$desired_replicas" ]]; then
    fail "only found $pod_count Running pod(s) for the current ${dep_label} rollout, expected $desired_replicas — cannot confirm ordering across all relevant replicas."
  fi
  while IFS='|' read -r pod_created pod_name; do
    [[ -z "$pod_created" ]] && continue
    log "${dep_label} replica '$pod_name' creationTimestamp=$pod_created (migration completionTime=$migrate_done)"
    if [[ "$migrate_done" > "$pod_created" ]]; then
      fail "ORDERING VIOLATION: migration Job '$migrate_job' completed ($migrate_done) AFTER ${dep_label} replica '$pod_name' was created ($pod_created) — 'migrations complete before application workloads advance' is NOT satisfied for this run."
    fi
  done <<<"$pod_lines"
  log "OBSERVED: migration completed at/before all $pod_count current ${dep_label} replica(s) for this release."
done

kctl -n "$namespace" get deploy,job,pods,svc

if $do_port_forward; then
  log "starting port-forwards: web on http://127.0.0.1:8080/  api on http://127.0.0.1:8000/  (Ctrl-C to stop)"
  kctl -n "$namespace" port-forward svc/web 8080:8080 >/tmp/gitops-mvp-verify-pf-web.log 2>&1 &
  web_pf=$!
  kctl -n "$namespace" port-forward svc/api 8000:8000 >/tmp/gitops-mvp-verify-pf-api.log 2>&1 &
  api_pf=$!
  trap 'kill "$web_pf" "$api_pf" 2>/dev/null || true' EXIT
  sleep 3

  check_http() {
    local desc="$1" url="$2"
    local code
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$url" || echo "000")
    log "curl $url -> $code ($desc)"
    if [[ "$code" != "200" ]]; then
      fail "$desc check failed: $url returned HTTP $code, expected 200"
    fi
  }
  check_http "api liveness" "http://127.0.0.1:8000/health"
  check_http "web root" "http://127.0.0.1:8080/"
  # DB-backed: /health explicitly never touches the database (apps/api/app/main.py);
  # /products does a real SELECT, so this is the actual check that would have
  # caught DEF-012's stale-credential defect (a broken DB password does not
  # surface through /health at all).
  check_http "api DB-backed (/products)" "http://127.0.0.1:8000/products"

  log "ALL CHECKS PASSED for release targetRevision=$requested_revision image_tag=$image_tag."
  log "port-forwards running in the foreground; press Ctrl-C to stop."
  wait "$web_pf" "$api_pf"
else
  log "ALL NON-HTTP CHECKS PASSED for release targetRevision=$requested_revision image_tag=$image_tag (--no-port-forward: HTTP/DB checks skipped, not proof of a working demo end to end)."
fi
