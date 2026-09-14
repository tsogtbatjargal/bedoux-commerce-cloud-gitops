#!/usr/bin/env bash
# GO-1 Gate 1 root/child Argo Application generation contract (design-contract
# tooling; not applied to any cluster — GO-2/GO-3 create the real repositories and
# install Argo CD). A multi-source Argo CD `Application` (`spec.sources`, Argo's
# native mechanism for pairing a chart source with a values-only source), with
# BOTH the root Application's own source and the child's env-values source pinned
# to the SAME explicit --env-revision commit SHA — never `HEAD`, never a branch
# name. The child's chart source is separately pinned to the release record's own
# `appRevision` SHA.
#
# DEF-006 fix — this script now actually GENERATES the child from the root's own
# source instead of taking the child's release-record/values paths directly as
# caller-supplied flags: --root-path is read as a directory, at --env-revision, in
# the env repo; it must contain exactly one child pointer file (a small YAML
# document declaring childAppName/releaseRecordPath/valuesPath). Multiple pointer
# files are refused — multi-child fan-out (real App-of-Apps enumeration) is
# explicitly out of scope for GO-1 (DEF-006's safe boundary: "one directly managed
# Application, no App-of-Apps claim"; deferred to GO-2/GO-3). This makes "the root
# produces the child" a property this script actually exercises, not just two
# independently parameterized renders that happen to agree.
#
# The release-record/values parsing, field validation, appRevision/chart-path
# verification and image repository/digest cross-check are now shared with
# scripts/render-gitops-release.sh via scripts/lib/gitops-release-binding.sh
# (DEF-006's other gap: this script previously had its own separate, weaker
# parser that never checked pairedAppRevision or image repository/digest
# consistency at all).
#
# DEF-005 fix — the child Application's values-only source previously set `path:`
# on the ref source (which also makes Argo treat it as a manifest-generating
# source, not a pure values reference — "unintended resource generation") AND
# referenced the values file in `helm.valueFiles` by basename only
# (`$values/values.yaml`, which Argo resolves from the REPO ROOT, not the actual
# file's directory — so a file at `env/values.yaml` was referenced as if it were
# at the repo root). The values-only source now carries ONLY `repoURL`,
# `targetRevision` and `ref` (no `path`), and `helm.valueFiles` references the
# full repo-relative path (`$values/env/values.yaml`), per
# https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/#values-files-from-external-git-repository.
#
# Why multi-source Application, not ApplicationSet: an ApplicationSet git generator
# still needs the exact same "pin to a commit, not a branch" discipline this script
# already provides directly, at the cost of an extra generator layer this project
# does not yet need (one root, one child pairing per environment; no fan-out across
# many near-identical environments today). A single multi-source Application is
# Argo CD's own native mechanism for "one chart source + one values source, pinned
# together" and needs no additional controller or CRD beyond Argo CD itself.

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
                        source points at. Must contain EXACTLY ONE child pointer
                        YAML file, declaring childAppName, releaseRecordPath and
                        valuesPath (each a path within the SAME --env-revision).
                        This script reads that pointer to generate the child
                        Application — it is the root's own source that produces
                        the child, not a caller-supplied shortcut. Zero or more
                        than one pointer file is refused (no App-of-Apps fan-out
                        yet; see DEF-006 in docs/DEFERRED-WORK.md).
  --root-app-name NAME  metadata.name for the rendered root Application.
  --env-repo-url URL    repoURL for the env-repo source(s).
  --app-repo-url URL    repoURL for the app-repo (chart) source.

Options:
  --app-repo PATH   Git repository appRevision is resolved against (default: this
                     repository's root). Override only for isolated local tests.
  --env-repo PATH   Git repository --env-revision is resolved against (default:
                     this repository's root). Override only for isolated local
                     tests.
  --namespace NAME  Destination namespace for the rendered child Application
                     (default: bedoux-<environment>, read from the release record).
  --help            Show this help.

Refuses (non-zero exit, no manifest emitted) on any of: malformed --env-revision
(including the literal strings "HEAD", "main", "master", or any non-40-hex value);
--env-revision does not exist as a commit; zero or multiple child pointer files
under --root-path at --env-revision; the pointer file is missing required fields;
the release record it points at cannot be read or is missing required fields;
malformed/nonexistent appRevision; chart path missing at appRevision; the values
file cannot be read; pairedAppRevision missing or mismatched; either image's
repository or digest in the values file not matching the release record.
EOF
}

env_revision=""
root_path=""
root_app_name=""
env_repo_url=""
app_repo_url=""
app_repo=""
env_repo=""
namespace=""

while (($#)); do
  case "$1" in
    --env-revision) env_revision="$2"; shift 2 ;;
    --root-path) root_path="$2"; shift 2 ;;
    --root-app-name) root_app_name="$2"; shift 2 ;;
    --env-repo-url) env_repo_url="$2"; shift 2 ;;
    --app-repo-url) app_repo_url="$2"; shift 2 ;;
    --app-repo) app_repo="$2"; shift 2 ;;
    --env-repo) env_repo="$2"; shift 2 ;;
    --namespace) namespace="$2"; shift 2 ;;
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

# --- Root generation: discover the child pointer under --root-path at the pinned ---
# --- --env-revision. This is the actual root-to-child generation step (DEF-006) — ---
# --- the caller names only the root's directory, never the child's own paths. ---
mapfile -t child_pointer_files < <(
  git -C "$env_repo" ls-tree -r --name-only "$env_revision" -- "$root_path" 2>/dev/null \
    | grep -E '\.ya?ml$' || true
)

if [[ "${#child_pointer_files[@]}" -eq 0 ]]; then
  echo "REFUSE: no child Application pointer file found under --root-path '$root_path' at env-revision '$env_revision'. The root Application's own source points at this path; it must contain exactly one child pointer for this script to generate a child from." >&2
  exit 1
fi
if [[ "${#child_pointer_files[@]}" -gt 1 ]]; then
  echo "REFUSE: ${#child_pointer_files[@]} child Application pointer files found under --root-path '$root_path' at env-revision '$env_revision' (${child_pointer_files[*]}). Multi-child fan-out (real App-of-Apps enumeration) is explicitly out of scope for GO-1 (DEF-006's safe boundary while deferred: one directly managed Application, no App-of-Apps claim) — deferred to GO-2/GO-3. Point --root-path at a directory containing exactly one pointer file." >&2
  exit 1
fi
pointer_path="${child_pointer_files[0]}"

pointer_content=$(gob_show "$env_repo" "$env_revision" "$pointer_path") || exit 1
child_app_name=$(gob_yaml_get "$pointer_content" childAppName)
release_record_path=$(gob_yaml_get "$pointer_content" releaseRecordPath)
values_path=$(gob_yaml_get "$pointer_content" valuesPath)

if [[ -z "$child_app_name" || -z "$release_record_path" || -z "$values_path" ]]; then
  echo "REFUSE: child pointer file '$pointer_path' (env-revision $env_revision) is missing one of: childAppName, releaseRecordPath, valuesPath" >&2
  exit 1
fi

gob_read_release_record "$env_repo" "$env_revision" "$release_record_path" || exit 1
gob_validate_app_revision "$app_repo" "$gob_release_app_revision" "$gob_release_chart_path" || exit 1
gob_crosscheck_values "$env_repo" "$env_revision" "$values_path" "$gob_release_app_revision" \
  "$gob_release_api_image" "$gob_release_web_image" || exit 1

app_revision="$gob_release_app_revision"
chart_path="$gob_release_chart_path"
environment="$gob_release_environment"
release_id="$gob_release_id"

if [[ -z "$namespace" ]]; then
  namespace="bedoux-${environment}"
fi

cat <<EOF
# Root Application: its OWN source is pinned to --env-revision ($env_revision),
# never HEAD/a branch. --root-path is the directory whose single child pointer
# file ('$pointer_path') this script actually read to generate the child
# Application below — see the header comment for why this proves root-to-child
# generation rather than two independently parameterized renders.
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
# Child Application for releaseId '${release_id}' (environment '${environment}'),
# generated from root pointer '${pointer_path}': a multi-source Application with
# the chart source pinned to the release record's own appRevision, and a SEPARATE
# values-only source pinned to the SAME env-revision as the root above — both
# exact commit SHAs, never a moving reference. The values-only source carries no
# 'path' (DEF-005: setting one makes Argo also treat it as manifest-generating,
# not a pure values reference) and 'helm.valueFiles' names the FULL repo-relative
# path from the ref root (DEF-005: a basename-only reference resolves from the
# repo root, not the file's actual directory).
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${child_app_name}
  namespace: argocd
spec:
  project: default
  sources:
    - repoURL: ${app_repo_url}
      targetRevision: ${app_revision}
      path: ${chart_path}
      helm:
        valueFiles:
          - \$values/${values_path}
    - repoURL: ${env_repo_url}
      targetRevision: ${env_revision}
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: ${namespace}
  syncPolicy: {}
EOF
