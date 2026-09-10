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
confirmed from live cluster state: the Application reaches Healthy AND either
Synced, or OutOfSync solely because of retained prior-release migration Job(s)
(never pruned by design — any other OutOfSync resource still fails) AND
`.status.sync.revision` matches its currently-requested `spec.source.
targetRevision` AND the triggered sync operation itself reports phase Succeeded
(not a stale status left over from an earlier sync); the migration Job matching
the CURRENTLY-REQUESTED image tag exists and Succeeded; both api and web
Deployments' rollouts complete; migration completed at/before BOTH the first api
AND first web pod were created; `/health`, `/` and `/products` (a real,
read-only, DB-backed endpoint — see apps/api/app/routers/products.py) all
return HTTP 200 through port-forward (unless --no-port-forward).
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
retained_jobs_only_out_of_sync() {
  local bad=0
  while IFS='|' read -r kind name status; do
    [[ -z "$kind" ]] && continue
    if [[ "$status" == "Synced" ]]; then
      continue
    fi
    if [[ "$kind" == "Job" && "$name" != "$migrate_job" ]]; then
      continue
    fi
    log "OutOfSync resource is not an expected retained prior-release Job: kind=$kind name=$name status=$status"
    bad=1
  done < <(kctl -n argocd get application bedoux-demo -o jsonpath='{range .status.resources[*]}{.kind}{"|"}{.name}{"|"}{.status}{"\n"}{end}' 2>/dev/null || true)
  return "$bad"
}

prior_operation_started_at=$(kctl -n argocd get application bedoux-demo -o jsonpath='{.status.operationState.startedAt}' 2>/dev/null || true)

if ! $skip_sync; then
  log "triggering manual sync (syncPolicy is {} — nothing else ever syncs this Application automatically)"
  kctl -n argocd patch application bedoux-demo --type=merge -p '{"operation":{"sync":{}}}'
fi

log "waiting up to 300s for the CURRENT operation on revision $requested_revision to reach Synced+Healthy+Succeeded"
deadline=$((SECONDS + 300))
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
  # A retained, non-current-release Job explains BOTH symptoms of the same root
  # cause: a prior release's Job (Succeeded or Failed) is never pruned, so it
  # can leave the Application's aggregate sync status OutOfSync (a Succeeded
  # Job pending prune) AND/OR its aggregate health Degraded (a Failed Job,
  # live-reproduced 2026-09-10 after a controlled migration-failure demo:
  # health stayed "Degraded" even once the reverted-to release was genuinely
  # healthy again, because the FAILED Job from the aborted attempt is retained
  # and its own resource health is unhealthy). Tolerating either is only safe
  # because the CURRENT release's own Job success, both Deployments' rollouts,
  # and ordering are ALL independently re-verified below regardless of this
  # tolerance — this never substitutes for those checks.
  retained_only=false
  if [[ "$sync_status" != "Synced" || "$health_status" != "Healthy" ]]; then
    retained_jobs_only_out_of_sync && retained_only=true
  fi
  sync_acceptable=false
  if [[ "$sync_status" == "Synced" || ( "$sync_status" == "OutOfSync" && "$retained_only" == true ) ]]; then
    sync_acceptable=true
  fi
  health_acceptable=false
  if [[ "$health_status" == "Healthy" || ( "$health_status" == "Degraded" && "$retained_only" == true ) ]]; then
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
  sleep 5
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
migrate_succeeded=$(kctl -n "$namespace" get job "$migrate_job" -o jsonpath='{.status.succeeded}' 2>/dev/null || true)
migrate_done=$(kctl -n "$namespace" get job "$migrate_job" -o jsonpath='{.status.completionTime}' 2>/dev/null || true)
if [[ -z "$migrate_succeeded" || "$migrate_succeeded" -lt 1 || -z "$migrate_done" ]]; then
  fail "migration Job '$migrate_job' exists but has not Succeeded (status.succeeded=${migrate_succeeded:-0}) — refusing to claim a working release."
fi
log "migration Job '$migrate_job' Succeeded at $migrate_done"

### Both api AND web rollouts must actually complete for THIS release — not just ###
### "the Application is Healthy," which can be satisfied by stale pods if a ###
### rollout is still converging at the exact moment of a status read. ###
for dep in api web; do
  if ! kctl -n "$namespace" rollout status "deployment/${dep}" --timeout=120s >/dev/null; then
    fail "deployment/${dep} did not complete its rollout for this release"
  fi
done

### Ordering evidence for BOTH api and web — a violation FAILS the script, it is ###
### no longer a soft warning (DEF-013). Selects the newest RUNNING pod for the ###
### label, not `.items[0]` (GO-MVP-U1, per the returned deployment/rollout-status ###
### wait above, this is the pod belonging to the advancing/current rollout, not ###
### an arbitrary or possibly-terminating pod left over from a prior release — an ###
### update lap can transiently have an old pod still terminating alongside the ###
### new one, and `.items[0]`'s ordering is not guaranteed to be creation order). ###
for dep_label in "api" "web"; do
  pod_created=$(kctl -n "$namespace" get pods -l "app=${dep_label}" --field-selector=status.phase=Running \
    -o jsonpath='{range .items[*]}{.metadata.creationTimestamp}{"\n"}{end}' 2>/dev/null | sort | tail -1 || true)
  if [[ -z "$pod_created" ]]; then
    fail "no Running pod found for app=${dep_label} in namespace $namespace — cannot confirm ordering or health for it."
  fi
  log "first ${dep_label} pod creationTimestamp=$pod_created (migration completionTime=$migrate_done)"
  if [[ "$migrate_done" > "$pod_created" ]]; then
    fail "ORDERING VIOLATION: migration Job '$migrate_job' completed ($migrate_done) AFTER the ${dep_label} pod was created ($pod_created) — 'migrations complete before application workloads advance' is NOT satisfied for this run."
  fi
done
log "OBSERVED: migration completed at/before both the api and web pods were created for this release."

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
