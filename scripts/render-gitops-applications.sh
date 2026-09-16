#!/usr/bin/env bash
# GO-1 Gate 1 root/child Argo Application generation contract (design-contract
# tooling; not applied to any cluster — GO-2/GO-3 create the real repositories and
# install Argo CD). A multi-source Argo CD `Application` (`spec.sources`, Argo's
# native mechanism for pairing a chart source with a values-only source). The
# root Application's own source is pinned to the caller's --env-revision — never
# `HEAD`, never a branch name. The child manifest is a checked-in artifact (see
# the App-of-Apps note below), so its own values-only source necessarily carries
# its OWN pinned commit SHA (a file cannot contain the hash of the commit that
# first introduces it); this script requires that SHA to be well-formed, exist,
# and be an ancestor-or-equal of --env-revision — never a moving reference, never
# from history --env-revision doesn't contain. The child's chart source is
# separately pinned to the release record's own `appRevision` SHA.
#
# DEF-006 fix, corrected (this revision) — a prior version of this script had
# --root-path point at a bespoke, non-Argo "child pointer" YAML file
# (childAppName/releaseRecordPath/valuesPath) that this script alone knew how to
# interpret, and re-templated the child Application text from scratch. That was
# NOT a real Argo-supported generation mechanism: the root Application it rendered
# had its own source.path point at that same directory, but a real Argo sync of
# the root would try to apply the pointer file itself as a Kubernetes resource —
# it is not a valid Application manifest, so nothing in real Argo semantics turns
# it into the child. The root and child text were only two independently
# parameterized renders that happened to agree with each other, not a proof that
# the root's source produces the child. See docs/gitops-go1-design-contract.md's
# "fifth round" corrections for the full reconciliation note; DEF-006 in
# docs/DEFERRED-WORK.md stayed open through that prior revision for this reason.
#
# The mechanism used now IS an Argo-native one: App-of-Apps. --root-path must
# contain, at --env-revision, exactly one ALREADY-RENDERED Argo CD `Application`
# manifest for the child (kind: Application, apiVersion argoproj.io/*) — the same
# kind of artifact a real "prepare release" step would commit into the env-repo,
# and the same kind of resource a real Argo sync of the root (source.path =
# --root-path) would apply verbatim as-is. That really is how App-of-Apps
# generation works in Argo: the root's sync applies whatever valid manifests it
# finds under its own source path; there is no separate templating step inside
# Argo itself for the child. This script's job is therefore to (a) discover that
# checked-in child manifest, (b) independently re-derive the release binding the
# SAME way render-gitops-release.sh does (via scripts/lib/gitops-release-binding.sh,
# reading the release record and values via provenance annotations on the child
# manifest), and (c) structurally validate — via a real YAML parse, not
# line-adjacency — that the checked-in child manifest's spec.sources match that
# independently-derived binding field-for-field. A tampered/injected field (for
# example a 'path' re-added to the values-only source) is refused, not silently
# accepted, because the structural comparison fails closed. Finally, this script
# proves "resolved pinned chart/values -> workload manifests" end to end by
# running the same helm-template step render-gitops-release.sh uses
# (scripts/lib/gitops-release-binding.sh's gob_render_workload_manifests) against
# the same binding.
#
# The release-record/values parsing, field validation, appRevision/chart-path
# verification, image repository/digest cross-check, and workload-manifest
# rendering are shared with scripts/render-gitops-release.sh via
# scripts/lib/gitops-release-binding.sh.
#
# DEF-005 fix (preserved from the prior revision) — the child Application's
# values-only source previously set `path:` on the ref source (which also makes
# Argo treat it as a manifest-generating source, not a pure values reference —
# "unintended resource generation") AND referenced the values file in
# `helm.valueFiles` by basename only (`$values/values.yaml`, which Argo resolves
# from the REPO ROOT, not the actual file's directory — so a file at
# `env/values.yaml` was referenced as if it were at the repo root). The values-only
# source now carries ONLY `repoURL`, `targetRevision` and `ref` (no `path`), and
# `helm.valueFiles` references the full repo-relative path
# (`$values/env/values.yaml`), per
# https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/#values-files-from-external-git-repository.
# gob_validate_child_manifest structurally enforces both halves of this fix on the
# checked-in child manifest, not just on this script's own template.
#
# Why App-of-Apps, not ApplicationSet: an ApplicationSet git generator still needs
# the exact same "pin to a commit, not a branch" discipline this script already
# provides directly, at the cost of an extra generator layer this project does not
# yet need (one root, one child pairing per environment; no fan-out across many
# near-identical environments today). App-of-Apps is Argo CD's own native
# mechanism for "a root Application whose source is a directory of other
# Application manifests" and needs no additional controller or CRD beyond Argo CD
# itself — see https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/.

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib/gitops-release-binding.sh
source "$repo_root/scripts/lib/gitops-release-binding.sh"

usage() {
  cat <<'EOF'
Usage: scripts/render-gitops-applications.sh --env-revision SHA
       --root-path PATH --root-app-name NAME
       --env-repo-url URL --app-repo-url URL [options]

Required:
  --env-revision SHA   40-hex-char git SHA-1. Pinned as targetRevision on BOTH the
                        root Application's source AND the child Application's
                        env-values source. Never HEAD, never a branch/tag name —
                        refused before touching git if not an exact 40-hex SHA.
  --root-path PATH     Path, within --env-revision, the root Application's own
                        source points at. The rendered root below carries no
                        'directory: {recurse: true}' (Argo's default is
                        non-recursive), so discovery here is non-recursive too —
                        matching what a real sync would actually do — and looks
                        ONLY at entries directly inside --root-path. That
                        directory must contain EXACTLY ONE entry: a checked-in
                        Argo CD Application manifest for the child (kind:
                        Application) — the real App-of-Apps mechanism: a sync of
                        the root applies whatever it finds here verbatim, so any
                        nested subdirectory or additional file alongside the
                        child manifest is refused as an unexpected resource a
                        real sync would also apply, not silently ignored. That
                        manifest must carry two annotations:
                        gitops.bedoux/release-record-path and
                        gitops.bedoux/values-path, each a path within the
                        manifest's OWN values-only source targetRevision (an
                        ancestor-or-equal of --env-revision — see below), so this
                        script can independently re-derive and structurally
                        cross-check its bound sources. Real multi-child fan-out
                        (enumerating many child Applications) is explicitly out
                        of scope for GO-1; see DEF-006 in docs/DEFERRED-WORK.md.
  --root-app-name NAME  metadata.name for the rendered root Application.
  --env-repo-url URL    repoURL for the env-repo source(s).
  --app-repo-url URL    repoURL for the app-repo (chart) source.

Options:
  --app-repo PATH   Git repository appRevision is resolved against (default: this
                     repository's root). Override only for isolated local tests.
  --env-repo PATH   Git repository --env-revision is resolved against (default:
                     this repository's root). Override only for isolated local
                     tests.
  --help            Show this help.

Refuses (non-zero exit, no manifest emitted) on any of: malformed --env-revision
(including the literal strings "HEAD", "main", "master", or any non-40-hex value);
--env-revision does not exist as a commit; --root-path missing/empty at
--env-revision; a nested subdirectory directly under --root-path; zero, multiple,
or any entry alongside the child manifest under --root-path (a real Argo sync
would apply all of them, not just the intended child); a non-.yaml/.yml or
structurally invalid (not kind: Application) manifest; the child manifest is
missing its release-record-path/values-path provenance annotations; the child
manifest's own values-only source targetRevision is malformed, a moving
reference, does not exist as a commit, or is not an ancestor-or-equal of
--env-revision; the release record it points at cannot be read or is missing
required fields; malformed/nonexistent appRevision; chart path missing at
appRevision; the values file cannot be read; pairedAppRevision missing or
mismatched; either image's repository or digest in the values file not matching
the release record; the checked-in child manifest's spec.sources do not
structurally match the independently-derived binding (including an injected
'path' on the values-only source, or any unsupported Helm/source override field
this tooling does not itself validate and render); spec.destination.server not
the expected in-cluster server, or spec.destination.namespace not matching the
'bedoux-<environment>' convention derived from the release record (this is also
the Helm rendering-context namespace, .Release.Namespace, used below); the
derived Helm release name (the child Application's own metadata.name) or
namespace not a valid DNS-1123 label; helm template failing against the
resolved chart/values in that exact rendering context.
EOF
}

env_revision=""
root_path=""
root_app_name=""
env_repo_url=""
app_repo_url=""
app_repo=""
env_repo=""

while (($#)); do
  case "$1" in
    --env-revision) env_revision="$2"; shift 2 ;;
    --root-path) root_path="$2"; shift 2 ;;
    --root-app-name) root_app_name="$2"; shift 2 ;;
    --env-repo-url) env_repo_url="$2"; shift 2 ;;
    --app-repo-url) app_repo_url="$2"; shift 2 ;;
    --app-repo) app_repo="$2"; shift 2 ;;
    --env-repo) env_repo="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

for req in env_revision root_path root_app_name env_repo_url app_repo_url; do
  if [[ -z "${!req}" ]]; then
    echo "Error: --env-revision, --root-path, --root-app-name, --env-repo-url and --app-repo-url are all required." >&2
    usage >&2
    exit 2
  fi
done

if [[ -z "$app_repo" ]]; then
  app_repo=$(git rev-parse --show-toplevel)
fi
if [[ -z "$env_repo" ]]; then
  env_repo=$(git rev-parse --show-toplevel)
fi

gob_require_sha "--env-revision" "$env_revision" || exit 1
gob_require_commit "--env-revision" "$env_repo" "$env_revision" || exit 1

# --- App-of-Apps discovery: find the single child Application manifest under ---
# --- --root-path at the pinned --env-revision. This is the real generation step ---
# --- (DEF-006) — a sync of the root by actual Argo CD would apply exactly this. ---
# --- The emitted root Application below carries no 'directory: {recurse: true}' ---
# --- (the field is omitted entirely, so Argo's own default — non-recursive — ---
# --- applies): a real sync of that root only ever looks at entries DIRECTLY ---
# --- inside --root-path, never nested subdirectories, and applies EVERY valid ---
# --- resource it finds there, not just ones named like a pointer/manifest. ---
# --- Discovery below is therefore also non-recursive, and treats ANY additional ---
# --- entry alongside the one child manifest — nested directory or extra file — ---
# --- as a mismatch worth refusing on, not silently ignoring. ---
mapfile -t root_entries < <(
  git -C "$env_repo" ls-tree "${env_revision}:${root_path}" 2>/dev/null || true
)
if [[ "${#root_entries[@]}" -eq 0 ]]; then
  echo "REFUSE: --root-path '$root_path' does not exist (or is empty) at env-revision '$env_revision'. A real Argo App-of-Apps sync of the root applies whatever is checked in there; this script refuses to invent a child." >&2
  exit 1
fi

nested_dirs=()
top_level_files=()
for entry in "${root_entries[@]}"; do
  entry_type=$(awk '{print $2}' <<<"$entry")
  entry_name=$(cut -f2 <<<"$entry")
  if [[ "$entry_type" == "tree" ]]; then
    nested_dirs+=("$entry_name")
  else
    top_level_files+=("$entry_name")
  fi
done

if [[ "${#nested_dirs[@]}" -gt 0 ]]; then
  echo "REFUSE: --root-path '$root_path' at env-revision '$env_revision' contains nested director(y/ies) (${nested_dirs[*]}). The root Application rendered below has no 'directory: {recurse: true}' (Argo's default is non-recursive), so a real sync of it would never look inside these — discovery must match that, not silently traverse into them. Either flatten --root-path to contain only the single child Application manifest, or this tooling needs an explicit, reviewed decision to opt into recursive discovery (not made yet — see DEF-006 in docs/DEFERRED-WORK.md)." >&2
  exit 1
fi

if [[ "${#top_level_files[@]}" -gt 1 ]]; then
  echo "REFUSE: --root-path '$root_path' at env-revision '$env_revision' contains ${#top_level_files[@]} entries (${top_level_files[*]}), not exactly one. A real Argo App-of-Apps sync of the root applies EVERY resource it finds directly under --root-path, not just an intended child Application — every one of these would be an unexpected resource applied alongside (or instead of) the child, and real multi-child fan-out (App-of-Apps enumeration across several children) is explicitly out of scope for GO-1 — deferred to GO-2/GO-3. Point --root-path at a directory containing exactly the one child Application manifest and nothing else." >&2
  exit 1
fi
pointer_path="${root_path%/}/${top_level_files[0]}"

if [[ "$pointer_path" != *.yaml && "$pointer_path" != *.yml ]]; then
  echo "REFUSE: the single entry under --root-path '$root_path' at env-revision '$env_revision' ('$pointer_path') is not a .yaml/.yml file, so it cannot be a valid Argo CD Application manifest." >&2
  exit 1
fi
child_manifest_content=$(gob_show "$env_repo" "$env_revision" "$pointer_path") || exit 1
child_kind=$(gob_yaml_get "$child_manifest_content" kind)
if [[ "$child_kind" != "Application" ]]; then
  echo "REFUSE: --root-path '$root_path' at env-revision '$env_revision' contains YAML ('$pointer_path') but it is not a valid Argo CD Application manifest (kind: Application; got kind='$child_kind'). A real Argo App-of-Apps sync of the root would refuse to reconcile whatever is there as a child Application." >&2
  exit 1
fi

child_app_name=$(gob_yaml_get "$child_manifest_content" metadata.name)
release_record_path=$(gob_yaml_get_annotation "$child_manifest_content" "gitops.bedoux/release-record-path")
values_path=$(gob_yaml_get_annotation "$child_manifest_content" "gitops.bedoux/values-path")

if [[ -z "$child_app_name" || -z "$release_record_path" || -z "$values_path" ]]; then
  echo "REFUSE: child Application manifest '$pointer_path' (env-revision $env_revision) is missing one of: metadata.name, the 'gitops.bedoux/release-record-path' annotation, the 'gitops.bedoux/values-path' annotation" >&2
  exit 1
fi

# --- The child manifest's OWN values-only source declares its own pinned commit ---
# --- (child_values_revision) — it cannot equal the commit that first introduces ---
# --- the manifest itself (a file cannot contain the hash of the commit that ---
# --- contains it), so it is read from the manifest, not assumed equal to the ---
# --- caller's --env-revision. It still must be a pinned SHA, exist, and be an ---
# --- ancestor-or-equal of --env-revision (never "from the future" relative to the ---
# --- root revision that references this manifest). The release record and values ---
# --- file the annotations point at are read AT child_values_revision, since ---
# --- that's the exact commit a real Argo sync of the child would pull them from. ---
child_values_revision=$(gob_child_values_revision "$child_manifest_content")
gob_require_sha "child Application manifest's values-only source targetRevision" "$child_values_revision" || exit 1
gob_require_commit "child Application manifest's values-only source targetRevision" "$env_repo" "$child_values_revision" || exit 1
if ! git -C "$env_repo" merge-base --is-ancestor "$child_values_revision" "$env_revision" 2>/dev/null; then
  echo "REFUSE: child Application manifest's values-only source targetRevision '$child_values_revision' is not an ancestor of (or equal to) --env-revision '$env_revision' — the child's own pinned values commit cannot be from history the root's pinned revision does not contain." >&2
  exit 1
fi

gob_read_release_record "$env_repo" "$child_values_revision" "$release_record_path" || exit 1
gob_validate_app_revision "$app_repo" "$gob_release_app_revision" "$gob_release_chart_path" || exit 1
gob_crosscheck_values "$env_repo" "$child_values_revision" "$values_path" "$gob_release_app_revision" \
  "$gob_release_api_image" "$gob_release_web_image" || exit 1

app_revision="$gob_release_app_revision"
chart_path="$gob_release_chart_path"
environment="$gob_release_environment"
release_id="$gob_release_id"
expected_namespace="bedoux-${environment}"

# --- Structural cross-check: the checked-in child manifest's own spec.sources ---
# --- (and spec.destination, which supplies the Helm rendering context below) ---
# --- must match this independently-derived binding field-for-field (real YAML ---
# --- parse, not line-adjacency) -- proves the artifact a real Argo App-of-Apps ---
# --- sync would apply is exactly what the reviewed release/values pairing binds. ---
gob_validate_child_manifest "$child_manifest_content" "$app_repo_url" "$app_revision" "$chart_path" \
  "$values_path" "$env_repo_url" "$child_values_revision" "$expected_namespace" || exit 1

# --- Rendering context: a real Argo sync of this child renders its Helm chart ---
# --- with .Release.Name = the Application's own metadata.name and ---
# --- .Release.Namespace = spec.destination.namespace — NOT the release record's ---
# --- releaseId, which Argo never sees. Both are derived from the (now ---
# --- structurally validated) checked-in manifest itself and passed explicitly ---
# --- into the shared renderer, so the workload-manifest proof below uses the ---
# --- same context a real sync would. ---
namespace=$(gob_yaml_get "$child_manifest_content" spec.destination.namespace)

cat <<EOF
# Root Application: its OWN source is pinned to --env-revision ($env_revision),
# never HEAD/a branch. source.path is --root-path itself ('$root_path'); a real
# Argo App-of-Apps sync of THIS root applies whatever Application manifests are
# checked in there verbatim — including the child manifest below, which is that
# exact checked-in artifact ('$pointer_path'), not something this script
# re-templates. See the header comment for why this is an actual Argo-supported
# generation mechanism, not two independently parameterized renders.
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${root_app_name}
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ${env_repo_url}
    targetRevision: ${env_revision}
    path: ${root_path}
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy: {}
---
EOF
printf '%s\n' "$child_manifest_content"

echo "Resolving pinned chart/values for releaseId '$release_id' (environment '$environment', child '$child_app_name', namespace '$namespace') into workload manifests, proving the root-to-child-to-workload chain end to end with the same rendering context a real Argo sync would use:" >&2
gob_render_workload_manifests "$app_repo" "$app_revision" "$chart_path" "$gob_values_content" "$child_app_name" "$namespace" || exit 1
