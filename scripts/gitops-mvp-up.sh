#!/usr/bin/env bash
# GO-MVP: bring up a minimal, local-only GitOps demo. Owner-approved reduced scope
# (docs/PROGRESS.md GO-MVP checklist entry, 2026-09-09) — explicitly NOT the full
# GO-1 design contract (docs/gitops-go1-design-contract.md), which stays paused,
# unmodified, and deferred (docs/DEFERRED-WORK.md DEF-001..011).
#
# What this does: one kind cluster, one dedicated namespace, Argo CD (pinned
# version) deploying the EXISTING charts/bedoux chart's api/web/Postgres from a
# LOCAL SNAPSHOT of the EXISTING bedoux-commerce-cloud repository (this checkout's
# own git history at a pinned commit — never pushed to the real GitHub remote; see
# "Why a local snapshot" below) via a single (not multi-source) Application,
# manual sync only (syncPolicy: {}), no self-heal/automatic recovery, no
# router/Ingress (browser access is via `kubectl port-forward`, see
# scripts/gitops-mvp-verify.sh). Migrations use charts/bedoux's sync-wave-ordered
# GitOps mode (`migration.gitopsMode=true`, this chart's existing opt-in flag) —
# see charts/bedoux/templates/migration-job.yaml's header comment for why the
# legacy Helm-hook form (ADR 0005) does not gate ordering correctly under Argo CD.
#
# Why a local snapshot, not the real GitHub remote directly: live-reproduced
# 2026-09-10 while first building this demo — Argo's Helm-hook-to-Argo-hook
# translation runs a `post-install,pre-upgrade` Job as PreSync unconditionally
# (Argo has no install-vs-upgrade distinction), before the chart's own
# ServiceAccount/Postgres exist, which is exactly what led to
# charts/bedoux/templates/migration-job.yaml's `migration.gitopsMode` flag and the
# sync-wave annotations across api-serviceaccount.yaml/postgres.yaml/api.yaml/
# web.yaml/ingress.yaml. Those fixes are real, permanent chart changes, but as of
# this writing they are UNCOMMITTED, dirty working-tree edits in this checkout
# (`git status` shows them modified, not committed — corrected per Codex's
# 2026-09-09T20:27:22-06:00 review, which caught an earlier, wrong "committed
# locally" claim here) and this script does not commit or push them to the shared
# repository's remote on your behalf; committing, reviewing and pushing that is a
# separate, explicit action. Until that happens, this script builds a LOCAL-ONLY
# git snapshot (this checkout's pinned --app-revision plus the current working
# tree's charts/bedoux/ directory overlaid on top, committed only to a throwaway
# branch inside the snapshot itself) and serves it to the in-cluster Argo CD via a
# hostPath mount on the kind node — never touching the real GitHub remote, and
# never committing anything in THIS repository's own working tree. Once these
# chart fixes are actually committed, pushed and reviewed upstream, re-run with
# --app-revision pointing at that real commit and this script needs no further
# changes (the file:// source pattern still works against a real remote too; it
# is not a permanent divergence).
#
# Deliberately does NOT use scripts/gitops_release_attempt_claim.py,
# scripts/gitops_paired_rollout_coordinator_model.py, or
# scripts/render-gitops-applications.sh's multi-source Application path — Codex's
# 2026-09-09T18:16:51-06:00 review found real defects in all three composed as
# documented (DEF-001, DEF-003, DEF-004, DEF-005). Per explicit owner instruction,
# this MVP does not use those known-broken automation paths.
#
# Secrets: the Postgres password is generated locally and passed to the Argo CD
# Application as an in-cluster-only Helm value (spec.source.helm.valuesObject) —
# never written to any file this script leaves behind, never committed.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/gitops-mvp-up.sh [options]

Options:
  --cluster-name NAME    kind cluster name (default: bedoux-gitops-mvp). Distinct
                          from the "bedoux" cluster the P-track scripts use, so
                          this demo never touches an existing local dev cluster.
  --namespace NAME       Demo namespace the Application deploys into
                          (default: bedoux-demo).
  --app-revision SHA     40-hex-char git commit SHA to pin as the base for the
                          local snapshot AND for locally-built images (default:
                          this checkout's current HEAD). Must exist as a real
                          commit; refused otherwise.
  --argocd-version VER   Argo CD version to install (default: v3.5.2 — the same
                          version researched/pinned in Gate 3 of the full design
                          contract, kept consistent rather than re-choosing).
  --dry-run              Print the steps and exit; contacts nothing.
  --help                 Show this help.

Requires on PATH: kind, kubectl, helm, podman, git, openssl. Requires a
`fs.inotify.max_user_instances` headroom on this host (kind/Argo CD create
several watchers) — see docs/local-tooling.md's inotify section if a repo-server
or controller pod CrashLoopBackOffs with "couldn't initialize inotify: too many
open files"; this script does not adjust that sysctl itself.

Refuses (non-zero exit) if: any required tool is missing; --app-revision is not a
well-formed, existing commit.
EOF
}

cluster_name="bedoux-gitops-mvp"
namespace="bedoux-demo"
app_revision=""
argocd_version="v3.5.2"
dry_run=false

while (($#)); do
  case "$1" in
    --cluster-name) cluster_name="$2"; shift 2 ;;
    --namespace) namespace="$2"; shift 2 ;;
    --app-revision) app_revision="$2"; shift 2 ;;
    --argocd-version) argocd_version="$2"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    --help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

log() { printf '[gitops-mvp-up] %s\n' "$1" >&2; }

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

for tool in kind kubectl helm podman git openssl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "REFUSE: required tool '$tool' not found on PATH" >&2
    exit 1
  fi
done

if [[ -z "$app_revision" ]]; then
  app_revision=$(git rev-parse HEAD)
fi
if ! [[ "$app_revision" =~ ^[0-9a-f]{40}$ ]]; then
  echo "REFUSE: --app-revision '$app_revision' is not a well-formed 40-hex-character git SHA-1" >&2
  exit 1
fi
if ! git cat-file -e "${app_revision}^{commit}" 2>/dev/null; then
  echo "REFUSE: --app-revision '$app_revision' does not exist as a commit in this checkout" >&2
  exit 1
fi
short_sha="${app_revision:0:12}"
image_tag="mvp-${short_sha}"
node_name="${cluster_name}-control-plane"
mount_path="/mnt/mvp-repo"

log "cluster=$cluster_name namespace=$namespace app_revision=$app_revision argocd_version=$argocd_version image_tag=$image_tag"

if $dry_run; then
  log "DRY-RUN: would create kind cluster '$cluster_name' (podman provider, single node)"
  log "DRY-RUN: would build+load localhost/bedoux-api:$image_tag and localhost/bedoux-web:$image_tag from commit $app_revision"
  log "DRY-RUN: would build a local-only git snapshot (base $app_revision + current charts/bedoux/ overlay) and mount it into the argocd-repo-server pod via hostPath — never pushed to the real remote"
  log "DRY-RUN: would install Argo CD $argocd_version into namespace argocd, patch argocd-cm so Ingress health is inert (no controller installed), patch argocd-repo-server to mount the local snapshot"
  log "DRY-RUN: would create namespace $namespace"
  log "DRY-RUN: would apply a single Application 'bedoux-demo' (source: local snapshot @ its pinned commit, path charts/bedoux, migration.gitopsMode=true, syncPolicy: {} manual only) targeting namespace $namespace"
  log "DRY-RUN: would trigger one manual sync and wait for Synced/Healthy"
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

### 1. Build the local-only snapshot repo (base --app-revision + current ###
### charts/bedoux/ working-tree overlay). Never touches the real remote. ###
snapshot="$work/mvp-src"
git clone --no-hardlinks -q "$repo_root" "$snapshot"
git -C "$snapshot" checkout -q "$app_revision" -b mvp-local
git -C "$snapshot" config user.email "mvp-demo@example.invalid"
git -C "$snapshot" config user.name "GO-MVP local demo"
rm -rf "$snapshot/charts/bedoux"
cp -r "$repo_root/charts/bedoux" "$snapshot/charts/bedoux"
git -C "$snapshot" add -A
if ! git -C "$snapshot" diff --cached --quiet; then
  git -C "$snapshot" commit -q -m "GO-MVP local-only snapshot: charts/bedoux overlaid from the current working tree (never pushed to origin)"
fi
snapshot_revision=$(git -C "$snapshot" rev-parse HEAD)
log "local snapshot commit: $snapshot_revision (base $app_revision + current charts/bedoux/ overlay)"

### 2. kind cluster (idempotent: skip creation if it already exists) — WITH the ###
### ownership check happening BEFORE any modification of a reused cluster. ###
### Corrected per Codex's GO-MVP review (docs/PROGRESS.md session log ###
### 2026-09-09T20:55:51-06:00, DEF-014): the prior version reused an existing, ###
### unmarked cluster, overwrote the node snapshot, loaded images, and installed/ ###
### patched Argo CD — ALL before ever checking ownership (the check happened much ###
### later, and even then only refused if an argocd/bedoux-demo Application already ###
### existed, otherwise it silently ADOPTED the unmarked cluster). Now: a reused ###
### cluster is checked for the ownership marker FIRST, before any other command ###
### touches it, and an unmarked cluster is refused outright, unconditionally — ###
### never adopted, regardless of what else may or may not already be running on it. ###
export KIND_EXPERIMENTAL_PROVIDER=podman
kctl() { kubectl --context "kind-$cluster_name" "$@"; }

if kind get clusters 2>/dev/null | grep -qx "$cluster_name"; then
  log "kind cluster '$cluster_name' already exists; checking ownership before touching it"
  if ! kctl -n kube-system get configmap bedoux-gitops-mvp-owner >/dev/null 2>&1; then
    echo "REFUSE: kind cluster '$cluster_name' already exists but has no kube-system/bedoux-gitops-mvp-owner marker — this does not look like a cluster gitops-mvp-up.sh created. Refusing to reuse, modify, or adopt it; use a different --cluster-name, or inspect/remove it manually first." >&2
    exit 1
  fi
  log "cluster ownership marker present — this cluster was created by gitops-mvp-up.sh; safe to reuse"
  kctl wait --for=condition=Ready node --all --timeout=120s
else
  cat >"$work/kind-config.yaml" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${cluster_name}
nodes:
  - role: control-plane
EOF
  log "creating kind cluster '$cluster_name' (delegated cgroup scope, per docs/local-tooling.md's verified pattern)"
  systemd-run --user --scope --slice=app.slice -p Delegate=yes \
    kind create cluster --name "$cluster_name" --config "$work/kind-config.yaml"
  kctl wait --for=condition=Ready node --all --timeout=120s
  # Mark ownership IMMEDIATELY, before anything else touches this brand-new
  # cluster — only ever created for a cluster THIS invocation just created,
  # never for a reused one (that would be adoption, exactly what this fix
  # removes).
  kctl -n kube-system create configmap bedoux-gitops-mvp-owner \
    --from-literal=created-by=scripts/gitops-mvp-up.sh \
    --from-literal=created-at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  log "marked cluster '$cluster_name' as owned by gitops-mvp-up.sh (kube-system/bedoux-gitops-mvp-owner)"
fi

### 3. Copy the local snapshot's .git onto the node, where the repo-server pod ###
### (patched below) will mount it. ###
podman exec "$node_name" mkdir -p "$mount_path"
podman exec "$node_name" rm -rf "$mount_path/mvp-src"
podman cp "$snapshot" "$node_name:$mount_path/mvp-src"
log "local snapshot copied onto the node at $mount_path/mvp-src"

### 4. Build api/web images from the PINNED commit's tree (git archive of the ###
### local snapshot, not the live working tree directly — so "pinned images" ###
### means built from the exact snapshot commit's source). ###
src="$work/src-${app_revision}"
mkdir -p "$src"
git -C "$snapshot" archive "$snapshot_revision" | tar -x -C "$src"
log "building localhost/bedoux-api:$image_tag from snapshot $snapshot_revision"
podman build -t "localhost/bedoux-api:${image_tag}" -f "$src/apps/api/Dockerfile" "$src/apps/api"
log "building localhost/bedoux-web:$image_tag from snapshot $snapshot_revision"
podman build -t "localhost/bedoux-web:${image_tag}" -f "$src/apps/web/Dockerfile" "$src/apps/web"
api_image_id=$(podman inspect --format '{{.Id}}' "localhost/bedoux-api:${image_tag}")
web_image_id=$(podman inspect --format '{{.Id}}' "localhost/bedoux-web:${image_tag}")
log "built api image id=$api_image_id web image id=$web_image_id (local podman storage IDs — this demo has no registry, so these are NOT registry digests; recorded here as the closest available local pin)"

### 5. Load images into the kind node (podman save + kind load image-archive; ###
### `kind load docker-image` does not work with kind's rootless-podman provider — ###
### documented workaround, docs/local-tooling.md). ###
for name in api web; do
  podman save -o "$work/bedoux-${name}.tar" "localhost/bedoux-${name}:${image_tag}"
  systemd-run --user --scope --slice=app.slice -p Delegate=yes \
    kind load image-archive "$work/bedoux-${name}.tar" --name "$cluster_name"
  rm -f "$work/bedoux-${name}.tar"
done
log "confirming images landed on the node"
podman exec "$node_name" crictl images 2>/dev/null | grep -E "bedoux-(api|web)" || {
  echo "REFUSE: built images not found on the kind node after load" >&2
  exit 1
}

### 6. Argo CD (pinned version, non-HA install manifest), then two targeted ###
### patches applied ONCE, before any Application exists: (a) argocd-cm's ###
### Ingress health customization — with no controller installed, Argo's ###
### default Ingress health check waits forever for a LoadBalancer address, ###
### which would keep the Application "Progressing" forever; (b) mount the local ###
### snapshot into argocd-repo-server. Both are applied in a single pass so the ###
### repo-server only ever rolls out once (a live-reproduced inotify-exhaustion ###
### risk on this host if multiple rollouts stack up — see docs/local-tooling.md). ###
kctl create namespace argocd --dry-run=client -o yaml | kctl apply -f -
log "installing Argo CD $argocd_version"
# --server-side: the combined install.yaml's applicationsets.argoproj.io CRD is
# large enough that client-side apply's last-applied-configuration annotation
# exceeds Kubernetes' 262144-byte annotation limit ("metadata.annotations: Too
# long"), reproduced live on the first attempt. Server-side apply doesn't store
# that annotation at all.
kctl apply -n argocd --server-side=true --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${argocd_version}/manifests/install.yaml"

log "patching argocd-cm: Ingress health is inert in this MVP (no controller installed)"
kctl -n argocd patch configmap argocd-cm --type=merge -p '{
  "data": {
    "resource.customizations.health.networking.k8s.io_Ingress": "hs = {}\nhs.status = \"Healthy\"\nhs.message = \"No Ingress controller installed in this local MVP (port-forward only); Ingress health is not meaningful here.\"\nreturn hs\n"
  }
}'

# Idempotency: a JSON-patch "add" to the end of an array is NOT idempotent — a
# second run against an already-patched Deployment (reusing the same cluster, as
# an update lap does) would append a SECOND "mvp-repo" volume/mount, which
# Kubernetes rejects outright ("Duplicate value"/"must be unique"). Only patch if
# the volume genuinely isn't there yet.
if kctl -n argocd get deployment argocd-repo-server -o jsonpath='{.spec.template.spec.volumes[*].name}' | grep -qw "mvp-repo"; then
  log "argocd-repo-server already has the mvp-repo mount (reused cluster); not patching again"
else
  log "patching argocd-repo-server to mount the local snapshot at ${mount_path}"
  kctl -n argocd patch deployment argocd-repo-server --type=json -p "[
    {\"op\":\"add\",\"path\":\"/spec/template/spec/volumes/-\",\"value\":{\"name\":\"mvp-repo\",\"hostPath\":{\"path\":\"${mount_path}\",\"type\":\"Directory\"}}},
    {\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/volumeMounts/-\",\"value\":{\"name\":\"mvp-repo\",\"mountPath\":\"${mount_path}\",\"readOnly\":true}},
    {\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/env/-\",\"value\":{\"name\":\"GIT_CONFIG_COUNT\",\"value\":\"1\"}},
    {\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/env/-\",\"value\":{\"name\":\"GIT_CONFIG_KEY_0\",\"value\":\"safe.directory\"}},
    {\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/env/-\",\"value\":{\"name\":\"GIT_CONFIG_VALUE_0\",\"value\":\"*\"}}
  ]"
fi
# `kubectl wait --for=condition=Available` is NOT sufficient here: the Deployment
# condition can be satisfied by the OLD (pre-patch) ReplicaSet's pod alone while
# the NEW (patched, hostPath-mounted) pod is still rolling out — reproduced live
# 2026-09-10. `rollout status` waits for the NEW ReplicaSet specifically.
log "waiting for the patched argocd-repo-server rollout to actually complete (bounded 90s first attempt)"
if ! kctl -n argocd rollout status deployment/argocd-repo-server --timeout=90s; then
  # Live-reproduced failure mode on this host: the new repo-server pod
  # CrashLoopBackOffs on "couldn't initialize inotify: too many open files"
  # while an old-ReplicaSet pod is still running alongside it during the
  # rolling update — see docs/local-tooling.md's inotify section. Scaling the
  # old ReplicaSet to 0 and deleting the crashing pod frees enough headroom for
  # the single remaining pod to start cleanly; this does not change any sysctl.
  log "rollout did not complete in time; checking for the known inotify-exhaustion pattern (old+new repo-server pods running simultaneously)"
  crashing_pod=$(kctl -n argocd get pods -l app.kubernetes.io/name=argocd-repo-server -o jsonpath='{range .items[?(@.status.phase!="Running")]}{.metadata.name}{"\n"}{end}' | head -1)
  running_but_unpatched=$(kctl -n argocd get pods -l app.kubernetes.io/name=argocd-repo-server -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[0].volumeMounts[?(@.name=="mvp-repo")]}{"\n"}{end}' | awk '$2=="" {print $1}')
  for p in $running_but_unpatched; do
    log "deleting stale pre-patch repo-server pod $p to free capacity"
    kctl -n argocd delete pod "$p" --wait=false || true
  done
  if [[ -n "$crashing_pod" ]]; then
    log "deleting crash-looping repo-server pod $crashing_pod so it restarts with less concurrent pressure"
    kctl -n argocd delete pod "$crashing_pod" --wait=false || true
  fi
  log "retrying rollout wait (bounded 120s)"
  kctl -n argocd rollout status deployment/argocd-repo-server --timeout=120s
fi
log "waiting for the rest of Argo CD core components (bounded 300s)"
kctl -n argocd wait --for=condition=Available --timeout=300s deployment/argocd-server
kctl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s

### 7. Demo namespace. Ownership was already verified/established in step 2, ###
### before anything above this point ever touched the cluster. ###
kctl create namespace "$namespace" --dry-run=client -o yaml | kctl apply -f -

### 8. Credential reuse (Codex's GO-MVP review, DEF-012): PostgreSQL only sets its ###
### password from POSTGRES_PASSWORD at first initdb — it does NOT update on a later ###
### changed env var. Regenerating a random password on every run, while reusing the ###
### same namespace/PVC/already-initialized Postgres data, would leave the Secret ###
### (and hence every NEW pod) with a password the already-running database does not ###
### actually have, breaking DB auth. If a previous run's Secret still exists in this ###
### namespace, reuse its exact password; only generate a fresh one for a genuinely ###
### new namespace/first run. ###
if kctl -n "$namespace" get secret postgres-credentials >/dev/null 2>&1; then
  postgres_password=$(kctl -n "$namespace" get secret postgres-credentials -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)
  log "reusing the existing Postgres credential from namespace '$namespace' (retained data, not regenerated)"
else
  postgres_password=$(openssl rand -hex 16)
  log "generated a fresh Postgres credential (no existing retained credential found in '$namespace')"
fi

### 9. A single (not multi-source) Application, manual sync only. Postgres ###
### password never written to any file this script leaves behind, never committed. ###
### Source is the local snapshot mounted above, referenced by its in-node path ###
### (never the real GitHub remote — see this script's header comment for why). ###
### `replicas` is deliberately NOT set here (Codex's GO-MVP review, DEF-012: a ###
### hardcoded `replicas: 1` override here would mask any `web.replicas`/`api.replicas` ###
### change made in charts/bedoux/values.yaml between demo runs) — the chart's own ###
### values.yaml default governs, so a real Git-tracked change to it is genuinely ###
### visible after the next sync, not silently overridden by this script. ###
### An Argo-native finalizer is set so deleting the Application actually cascades to ###
### its managed resources (the prior version claimed this without declaring it). ###
cat >"$work/application.yaml" <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: bedoux-demo
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${mount_path}/mvp-src
    targetRevision: ${snapshot_revision}
    path: charts/bedoux
    helm:
      valuesObject:
        api:
          image:
            repository: localhost/bedoux-api
            tag: "${image_tag}"
            pullPolicy: IfNotPresent
        web:
          image:
            repository: localhost/bedoux-web
            tag: "${image_tag}"
            pullPolicy: IfNotPresent
        postgres:
          password: "${postgres_password}"
        migration:
          gitopsMode: true
        seed:
          enabled: false
        canary:
          enabled: false
        ingress:
          # No router installed in this MVP (port-forward only, per owner
          # instruction); an empty className keeps the rendered Ingress object
          # honestly inert rather than referencing a controller that is not there.
          className: ""
  destination:
    server: https://kubernetes.default.svc
    namespace: ${namespace}
  # Manual sync only, no self-heal, no automated recovery — exactly the owner's
  # instruction for this MVP. Deferred: automated recovery is DEF-001/002/003.
  syncPolicy: {}
EOF
unset postgres_password
kctl apply -f "$work/application.yaml"

log "Application 'bedoux-demo' created/updated (OutOfSync expected until the next sync)."
log "Next: run scripts/gitops-mvp-verify.sh to sync and wait for Healthy."
log "up complete. snapshot_revision=${snapshot_revision} image_tag=${image_tag}"
