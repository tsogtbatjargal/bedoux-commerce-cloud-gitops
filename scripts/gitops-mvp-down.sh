#!/usr/bin/env bash
# GO-MVP: scoped, idempotent cleanup. Removes ONLY resources this demo's own
# scripts created (the Application, the demo namespace, the kind cluster this
# script itself marked as owned, and the exact locally-built images this
# specific run's Application declared) — never anything else. Matches
# AGENTS.md's same-day-teardown default and "preserve unrelated work."
#
# Corrected per Codex's GO-MVP review (docs/PROGRESS.md session log
# 2026-09-09T20:27:22-06:00, DEF-014): an inventory-query FAILURE was previously
# indistinguishable from "no cluster exists" — refuses instead of guessing; an
# already-clean run previously exited 1 (pipefail + grep-no-match on an image
# sweep) — fixed; a REUSED, same-named cluster is refused (never adopted) unless
# it carries the ownership marker gitops-mvp-up.sh sets; the Application's own
# Argo CD finalizer now actually cascades deletion of its managed resources
# (gitops-mvp-up.sh sets `resources-finalizer.argocd.argoproj.io`).
#
# Corrected AGAIN per Codex's follow-up review (docs/PROGRESS.md session log
# 2026-09-09T20:55:51-06:00, DEF-014): the broad `mvp-*` image-sweep fallback
# was itself unsafe — reproduced live with mocks: it deleted a synthetic,
# genuinely UNRELATED `localhost/bedoux-api:mvp-another-demo` image whenever the
# exact tag could not be read, and a `podman images` query failure (exit 125)
# was silently swallowed by `|| true` and reported as "no matching images,
# cleanup complete" instead of a failure. That fallback is REMOVED entirely: if
# the exact tag cannot be read from a live Application, image cleanup is
# SKIPPED and reported as skipped, never guessed. Deletion/removal failures
# (Application, namespace, images) now cause this script to exit non-zero
# instead of being downgraded to a log line while the script still exits 0.

set -uo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/gitops-mvp-down.sh [options]

Options:
  --cluster-name NAME   kind cluster name (default: bedoux-gitops-mvp).
  --namespace NAME      Demo namespace (default: bedoux-demo).
  --keep-cluster         Remove the Application/namespace/images but leave the
                          kind cluster and Argo CD installed (faster re-runs).
  --dry-run              Print exactly what would be deleted (cluster,
                          namespace, images) without deleting anything.
  --help                 Show this help.

Deletes, in order: the 'bedoux-demo' Application (its own
`resources-finalizer.argocd.argoproj.io` finalizer, set by gitops-mvp-up.sh,
cascades deletion of its managed resources); the demo namespace (a backstop, in
case the Application or its finalizer is absent); the kind cluster named above
(unless --keep-cluster); and the EXACT 'localhost/bedoux-api'/
'localhost/bedoux-web' image tag read from the live Application before it was
deleted. There is NO broader image-cleanup fallback: if the exact tag cannot be
read (the Application/cluster is already gone or unreadable), image cleanup is
explicitly SKIPPED and reported as skipped — it never guesses, and never sweeps
by name-prefix alone. Never touches any other kind cluster, namespace, or image.

Refuses (non-zero exit, deletes nothing) if: the kind inventory query itself
fails (distinct from a confirmed-empty inventory); a cluster with the given
name exists but lacks this demo's own ownership marker
(kube-system/bedoux-gitops-mvp-owner, set by gitops-mvp-up.sh) — this is
presumed to be a cluster this script did not create, and is left untouched.

Exits non-zero if any deletion/removal step that was actually attempted failed
— a failure is never downgraded to a log line while still reporting success.
EOF
}

cluster_name="bedoux-gitops-mvp"
namespace="bedoux-demo"
keep_cluster=false
dry_run=false

while (($#)); do
  case "$1" in
    --cluster-name) cluster_name="$2"; shift 2 ;;
    --namespace) namespace="$2"; shift 2 ;;
    --keep-cluster) keep_cluster=true; shift ;;
    --dry-run) dry_run=true; shift ;;
    --help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

log() { printf '[gitops-mvp-down] %s\n' "$1" >&2; }
export KIND_EXPERIMENTAL_PROVIDER=podman
failed=0

### Inventory: distinguish "confirmed empty" from "query failed" — a failed ###
### query must never be silently treated as "nothing to clean up." ###
cluster_list_output=""
if ! cluster_list_output=$(kind get clusters 2>&1); then
  echo "REFUSE: 'kind get clusters' failed (not a confirmed-empty result): $cluster_list_output" >&2
  echo "Not proceeding — a failed inventory query is never treated as proof there is nothing to delete." >&2
  exit 1
fi

cluster_exists=false
if grep -qx "$cluster_name" <<<"$cluster_list_output"; then
  cluster_exists=true
fi

exact_image_tag=""

if ! $cluster_exists; then
  log "kind cluster '$cluster_name' does not exist (confirmed via kind get clusters); nothing to delete there"
else
  kctl() { kubectl --context "kind-$cluster_name" "$@"; }

  ### Ownership check — refuse to touch a same-named cluster this script did ###
  ### not itself create. ###
  if ! kctl -n kube-system get configmap bedoux-gitops-mvp-owner >/dev/null 2>&1; then
    echo "REFUSE: kind cluster '$cluster_name' exists but has no kube-system/bedoux-gitops-mvp-owner marker — this does not look like a cluster gitops-mvp-up.sh created. Refusing to modify or delete it; pass a different --cluster-name if this is intentional, or remove it manually after confirming it is safe to do so." >&2
    exit 1
  fi

  ### Read the exact release tag from the live Application BEFORE deleting ###
  ### anything, so image cleanup can be scoped precisely — and ONLY then. ###
  if kctl -n argocd get application bedoux-demo >/dev/null 2>&1; then
    exact_image_tag=$(kctl -n argocd get application bedoux-demo -o jsonpath='{.spec.source.helm.valuesObject.api.image.tag}' 2>/dev/null || true)
  fi

  if $dry_run; then
    log "DRY-RUN: would delete Application 'bedoux-demo' (namespace argocd) — cascades via its own finalizer"
    log "DRY-RUN: would delete namespace '$namespace'"
    if $keep_cluster; then
      log "DRY-RUN: --keep-cluster set — would leave kind cluster '$cluster_name' and Argo CD installed"
    else
      log "DRY-RUN: would delete kind cluster '$cluster_name'"
    fi
    if [[ -n "$exact_image_tag" ]]; then
      log "DRY-RUN: would remove localhost/bedoux-api:${exact_image_tag} and localhost/bedoux-web:${exact_image_tag} (exact tag read from the live Application)"
    else
      log "DRY-RUN: could not read an exact tag from the Application — image cleanup would be SKIPPED (no broader fallback sweep is ever performed)"
    fi
    exit 0
  fi

  log "deleting Application 'bedoux-demo' (if present) — its own resources-finalizer.argocd.argoproj.io finalizer cascades deletion of its managed resources"
  if ! kctl -n argocd delete application bedoux-demo --ignore-not-found --wait=true --timeout=120s; then
    log "FAILURE: Application delete did not confirm within timeout"
    failed=1
  fi

  log "deleting namespace '$namespace' (if present) — a backstop in case the Application/finalizer was absent"
  if ! kctl delete namespace "$namespace" --ignore-not-found --wait=true --timeout=120s; then
    log "FAILURE: namespace delete did not confirm within timeout"
    failed=1
  fi

  if $keep_cluster; then
    log "--keep-cluster set: leaving kind cluster '$cluster_name', Argo CD, and the ownership marker in place"
  else
    log "deleting kind cluster '$cluster_name' (owned by this demo, confirmed above)"
    if ! kind delete cluster --name "$cluster_name"; then
      log "FAILURE: kind delete cluster did not succeed"
      failed=1
    fi
  fi
fi

if $dry_run; then
  # cluster_exists was false: nothing to preview beyond "nothing to delete."
  log "DRY-RUN: no cluster existed to inspect for an exact release tag; image cleanup would be SKIPPED (no broader fallback sweep is ever performed)"
  exit 0
fi

### Image cleanup: ONLY the exact tag read from the live Application above. ###
### No fallback sweep by name prefix — reproduced live (mocks) that the prior ###
### 'mvp-*' fallback deleted a genuinely unrelated image when the exact tag ###
### could not be determined. Uncertainty here means "skip," never "guess." ###
remove_image() {
  local img="$1"
  local exists_rc
  podman image exists "$img" 2>/dev/null
  exists_rc=$?
  if [[ "$exists_rc" -eq 0 ]]; then
    log "removing $img"
    if ! podman rmi "$img" >/dev/null 2>&1; then
      log "FAILURE: could not remove $img (may still be referenced)"
      failed=1
    fi
  elif [[ "$exists_rc" -eq 1 ]]; then
    log "$img does not exist locally — nothing to remove"
  else
    log "FAILURE: could not determine whether $img exists (podman image exists returned $exists_rc) — not attempting removal"
    failed=1
  fi
}

if [[ -n "$exact_image_tag" ]]; then
  log "removing images for the exact release tag read from the Application: ${exact_image_tag}"
  remove_image "localhost/bedoux-api:${exact_image_tag}"
  remove_image "localhost/bedoux-web:${exact_image_tag}"
else
  log "no exact release tag was available (cluster/Application already gone or unreadable) — SKIPPING image cleanup rather than guessing which images belong to this demo. Remove them manually if you know the exact tag, e.g.: podman rmi localhost/bedoux-api:<tag> localhost/bedoux-web:<tag>"
fi

if [[ "$failed" -ne 0 ]]; then
  echo "REFUSE: one or more cleanup steps failed — see FAILURE lines above. Not reporting success." >&2
  exit 1
fi

log "cleanup complete. Verify: 'kind get clusters' should not list '$cluster_name' (unless --keep-cluster was used)."
