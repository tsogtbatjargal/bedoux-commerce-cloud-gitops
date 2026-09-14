# Shared, sourced-only helpers for the GO-1 root/child binding scripts
# (render-gitops-release.sh, render-gitops-applications.sh). Not executable on its
# own — has no shebang and no set -euo pipefail of its own; it inherits the
# caller's shell options.
#
# Extracted per DEF-006's "shared release validation is not actually reused by the
# Application renderer" gap: before this, render-gitops-applications.sh had its own
# separate, weaker release-record parser (no chart-path-existence check, no
# pairedAppRevision/image cross-check at all) even though its own header comment
# claimed it was "reusing render-gitops-release.sh's binding logic, not a second
# implementation of it." That claim was false; this file makes it true. Both
# scripts now run the identical release-record + values validation, including the
# image repository/digest cross-check that render-gitops-applications.sh
# previously skipped entirely.

gob_require_sha() {
  # $1 = flag/field name for error text, $2 = value to check.
  local flag="$1" value="$2"
  case "$value" in
    HEAD|main|master|origin/*|refs/*)
      echo "REFUSE: $flag '$value' looks like a moving reference (branch/HEAD/remote-tracking), not a pinned commit SHA. This tooling only ever accepts an exact 40-hex-character git SHA-1, so rendered output can never silently track a moving branch." >&2
      return 1
      ;;
  esac
  if ! [[ "$value" =~ ^[0-9a-f]{40}$ ]]; then
    echo "REFUSE: $flag '$value' is not a well-formed 40-hex-character git SHA-1; refusing before touching git" >&2
    return 1
  fi
  return 0
}

gob_require_commit() {
  # $1 = flag/field name, $2 = repo, $3 = sha.
  local flag="$1" repo="$2" sha="$3"
  if ! git -C "$repo" cat-file -e "${sha}^{commit}" 2>/dev/null; then
    echo "REFUSE: $flag '$sha' does not exist as a commit in '$repo'" >&2
    return 1
  fi
  return 0
}

gob_show() {
  # $1 = repo, $2 = revision, $3 = path. Prints content on stdout; on failure
  # prints a REFUSE message to stderr and returns 1 without printing anything.
  local repo="$1" revision="$2" path="$3" content
  if ! content=$(git -C "$repo" show "${revision}:${path}" 2>&1); then
    echo "REFUSE: could not read '$path' at env-revision '$revision' in '$repo': $content" >&2
    return 1
  fi
  printf '%s' "$content"
  return 0
}

gob_yaml_get() {
  python3 -c '
import sys, yaml
d = yaml.safe_load(sys.argv[1]) or {}
path = sys.argv[2].split(".")
for p in path:
    d = (d or {}).get(p, {}) if isinstance(d, dict) else ""
print(d if isinstance(d, str) else (d or ""))
' "$1" "$2"
}

gob_read_release_record() {
  # $1 = env_repo, $2 = env_revision, $3 = release_record_path.
  # On success, sets (globals, caller's shell): gob_release_content,
  # gob_release_app_revision, gob_release_chart_path, gob_release_environment,
  # gob_release_id, gob_release_api_image, gob_release_web_image. On failure,
  # prints a REFUSE message and returns 1; the gob_release_* vars are unset/stale.
  local env_repo="$1" env_revision="$2" path="$3"
  gob_release_content=$(gob_show "$env_repo" "$env_revision" "$path") || return 1

  gob_release_app_revision=$(gob_yaml_get "$gob_release_content" appRevision)
  gob_release_chart_path=$(gob_yaml_get "$gob_release_content" chart.path)
  gob_release_environment=$(gob_yaml_get "$gob_release_content" environment)
  gob_release_id=$(gob_yaml_get "$gob_release_content" releaseId)
  gob_release_api_image=$(gob_yaml_get "$gob_release_content" images.api)
  gob_release_web_image=$(gob_yaml_get "$gob_release_content" images.web)

  if [[ -z "$gob_release_app_revision" || -z "$gob_release_chart_path" || -z "$gob_release_environment" \
        || -z "$gob_release_id" || -z "$gob_release_api_image" || -z "$gob_release_web_image" ]]; then
    echo "REFUSE: release record at '$path' (env-revision $env_revision) is missing one of: appRevision, chart.path, environment, releaseId, images.api, images.web" >&2
    return 1
  fi
  gob_require_sha "appRevision" "$gob_release_app_revision" || return 1
  return 0
}

gob_validate_app_revision() {
  # $1 = app_repo, $2 = app_revision, $3 = chart_path. Verifies the commit exists
  # and the chart path exists at that exact commit — never falls back to the
  # working tree or HEAD.
  local app_repo="$1" app_revision="$2" chart_path="$3"
  if ! git -C "$app_repo" cat-file -e "${app_revision}^{commit}" 2>/dev/null; then
    echo "REFUSE: appRevision '$app_revision' does not exist as a commit in '$app_repo'; refusing to fall back to the working tree or HEAD" >&2
    return 1
  fi
  if ! git -C "$app_repo" cat-file -e "${app_revision}:${chart_path}" 2>/dev/null; then
    echo "REFUSE: chart path '$chart_path' does not exist at commit '$app_revision' in '$app_repo'" >&2
    return 1
  fi
  return 0
}

gob_crosscheck_values() {
  # $1 = env_repo, $2 = env_revision, $3 = values_path, $4 = app_revision (the
  # release record's own appRevision), $5 = record_api_image ("repo@digest"),
  # $6 = record_web_image ("repo@digest"). On success sets gob_values_content.
  local env_repo="$1" env_revision="$2" values_path="$3" app_revision="$4"
  local record_api_image="$5" record_web_image="$6"
  gob_values_content=$(gob_show "$env_repo" "$env_revision" "$values_path") || return 1

  local paired_app_revision values_api_digest values_web_digest values_api_repo values_web_repo
  paired_app_revision=$(gob_yaml_get "$gob_values_content" pairedAppRevision)
  values_api_digest=$(gob_yaml_get "$gob_values_content" api.image.digest)
  values_web_digest=$(gob_yaml_get "$gob_values_content" web.image.digest)
  values_api_repo=$(gob_yaml_get "$gob_values_content" api.image.repository)
  values_web_repo=$(gob_yaml_get "$gob_values_content" web.image.repository)

  if [[ -z "$paired_app_revision" ]]; then
    echo "REFUSE: values file '$values_path' does not declare pairedAppRevision — this is mandatory, not optional; refusing to render an unverifiable pairing" >&2
    return 1
  fi
  if [[ "$paired_app_revision" != "$app_revision" ]]; then
    echo "REFUSE: mixed-revision mismatch — release record pins appRevision '$app_revision' but values file '$values_path' declares pairedAppRevision '$paired_app_revision'. Refusing to render an inconsistent pairing." >&2
    return 1
  fi

  local record_api_repo="${record_api_image%%@*}"
  local record_web_repo="${record_web_image%%@*}"
  local record_api_digest="${record_api_image##*@}"
  local record_web_digest="${record_web_image##*@}"

  # Repository identity is checked SEPARATELY from digest: a digest is
  # content-addressed and says nothing about which registry/repository it was
  # pulled from. See render-gitops-release.sh's original header note for the
  # reproduced counterexample this closes.
  if [[ -z "$values_api_repo" || "$values_api_repo" != "$record_api_repo" ]]; then
    echo "REFUSE: mismatched API image repository — release record's images.api repository is '$record_api_repo' but values file '$values_path' declares api.image.repository '$values_api_repo'. Refusing to render an artifact whose provenance/registry binding does not match the reviewed release, even if the digest matches." >&2
    return 1
  fi
  if [[ -z "$values_web_repo" || "$values_web_repo" != "$record_web_repo" ]]; then
    echo "REFUSE: mismatched web image repository — release record's images.web repository is '$record_web_repo' but values file '$values_path' declares web.image.repository '$values_web_repo'. Refusing to render an artifact whose provenance/registry binding does not match the reviewed release, even if the digest matches." >&2
    return 1
  fi
  if [[ -z "$values_api_digest" || "$values_api_digest" != "$record_api_digest" ]]; then
    echo "REFUSE: mismatched API image digest — release record's images.api digest is '$record_api_digest' but values file '$values_path' declares api.image.digest '$values_api_digest'. Refusing to render an unreviewed artifact." >&2
    return 1
  fi
  if [[ -z "$values_web_digest" || "$values_web_digest" != "$record_web_digest" ]]; then
    echo "REFUSE: mismatched web image digest — release record's images.web digest is '$record_web_digest' but values file '$values_path' declares web.image.digest '$values_web_digest'. Refusing to render an unreviewed artifact." >&2
    return 1
  fi
  return 0
}
