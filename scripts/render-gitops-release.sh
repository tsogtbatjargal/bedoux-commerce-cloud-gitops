#!/usr/bin/env bash
# GO-1 Gate 1 root/child binding-render contract (design-contract tooling; not
# wired into any Argo Application yet — GO-2/GO-3 do that).
#
#   ROOT  = an explicit, verified env-repo commit (--env-revision) — the caller's
#           trusted pin, exactly as Argo would be pointed at a specific reviewed
#           revision. It is NOT re-derived from file content: a commit's hash is a
#           property of history, not something a file inside that commit can
#           usefully self-declare (a file cannot contain the hash of the commit
#           that contains it without a circular dependency).
#   CHILD = the rendered manifests produced by reading the release record AND the
#           values file from THAT SAME pinned commit (never from an arbitrary live
#           path — both go through `git show <env-revision>:<path>`), cross-checking
#           the values file's pairedAppRevision and per-image digests against the
#           release record's own declarations, then extracting the chart from the
#           release record's appRevision via `git archive` and rendering.
#
# Nothing here can be affected by uncommitted working-tree state: every input is
# extracted from a git object at an explicit, verified commit. --app-repo/--env-repo
# default to this repository (there is no separate bedoux-commerce-env repo yet —
# GO-2 creates one); overriding them lets local tests use an isolated scratch git
# repo instead of requiring real commits here.
#
# The release-record/values parsing, field validation, appRevision/chart-path
# verification and image repository/digest cross-check live in
# scripts/lib/gitops-release-binding.sh, shared with
# scripts/render-gitops-applications.sh (DEF-006: closes "shared release validation
# is not actually reused" — both scripts now run the identical checks).

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib/gitops-release-binding.sh
source "$repo_root/scripts/lib/gitops-release-binding.sh"

usage() {
  cat <<'EOF'
Usage: scripts/render-gitops-release.sh --env-revision SHA
       --release-record-path PATH --values-path PATH [options]

Required:
  --env-revision SHA          40-hex-char git SHA-1. Both --release-record-path and
                               --values-path are extracted from the repo at exactly
                               this commit (git show), never from a live path.
  --release-record-path PATH  Path, within --env-revision, to the release record.
                               Must declare: environment, releaseId, appRevision,
                               chart.path, images.api, images.web.
  --values-path PATH          Path, within --env-revision, to the paired Helm
                               values overlay. Must declare pairedAppRevision
                               (mandatory — refused if absent) and, for each of
                               api/web, both image.repository AND image.digest
                               (checked separately — a matching digest under a
                               different repository is refused, not just a
                               mismatched digest).

Options:
  --app-repo PATH   Git repository appRevision is resolved against (default: this
                     repository's root). Override only for isolated local tests
                     against a scratch repo.
  --env-repo PATH   Git repository --env-revision is resolved against (default:
                     this repository's root — there is no separate env repo until
                     GO-2). Override only for isolated local tests.
  --out-dir DIR     Directory to extract the pinned chart source into (default: a
                     fresh mktemp -d, removed on exit unless --out-dir is given
                     explicitly, in which case it is left for inspection).
  --help            Show this help.

Refuses (non-zero exit, no helm invocation) on any of: malformed/moving
--env-revision; --env-revision does not exist as a commit; the release record
cannot be read at that commit or is missing required fields; malformed/nonexistent
appRevision; chart path missing at appRevision; the values file cannot be read at
--env-revision; pairedAppRevision missing or not equal to the release record's
appRevision; either image's repository in the values file not equal to the release
record's declared repository for that image (checked independently of digest);
either image's digest in the values file not equal to the release record's
declared digest for that image.
EOF
}

env_revision=""
release_record_path=""
values_path=""
app_repo=""
env_repo=""
out_dir=""
keep_out_dir=false

while (($#)); do
  case "$1" in
    --env-revision) env_revision="$2"; shift 2 ;;
    --release-record-path) release_record_path="$2"; shift 2 ;;
    --values-path) values_path="$2"; shift 2 ;;
    --app-repo) app_repo="$2"; shift 2 ;;
    --env-repo) env_repo="$2"; shift 2 ;;
    --out-dir) out_dir="$2"; keep_out_dir=true; shift 2 ;;
    --help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$env_revision" || -z "$release_record_path" || -z "$values_path" ]]; then
  echo "Error: --env-revision, --release-record-path and --values-path are all required." >&2
  usage >&2
  exit 2
fi

if [[ -z "$app_repo" ]]; then
  app_repo=$(git rev-parse --show-toplevel)
fi
if [[ -z "$env_repo" ]]; then
  env_repo=$(git rev-parse --show-toplevel)
fi

gob_require_sha "--env-revision" "$env_revision" || exit 1
gob_require_commit "--env-revision" "$env_repo" "$env_revision" || exit 1

gob_read_release_record "$env_repo" "$env_revision" "$release_record_path" || exit 1
gob_validate_app_revision "$app_repo" "$gob_release_app_revision" "$gob_release_chart_path" || exit 1
gob_crosscheck_values "$env_repo" "$env_revision" "$values_path" "$gob_release_app_revision" \
  "$gob_release_api_image" "$gob_release_web_image" || exit 1

app_revision="$gob_release_app_revision"
chart_path="$gob_release_chart_path"
release_id="$gob_release_id"
record_api_digest="${gob_release_api_image##*@}"
record_web_digest="${gob_release_web_image##*@}"

if [[ -z "$out_dir" ]]; then
  out_dir=$(mktemp -d)
fi

echo "Rendering release '$release_id': chart pinned at appRevision $app_revision ($chart_path in $app_repo), values pinned at envRevision $env_revision ($values_path in $env_repo), image digests cross-checked (api=$record_api_digest web=$record_web_digest)" >&2
if ! gob_render_workload_manifests "$app_repo" "$app_revision" "$chart_path" "$gob_values_content" "$release_id" "" "$out_dir"; then
  [[ "$keep_out_dir" == false ]] && rm -rf "$out_dir"
  exit 1
fi

[[ "$keep_out_dir" == false ]] && rm -rf "$out_dir"
exit 0
