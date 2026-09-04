#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
chart_dir="$repo_root/charts/bedoux"
fixture_dir=""

cleanup() {
  if [[ -n "$fixture_dir" && -d "$fixture_dir" && "$fixture_dir" == /tmp/bedoux-p14-resource-test.* ]]; then
    rm -rf -- "$fixture_dir"
  fi
}
trap cleanup EXIT

deployment_document() {
  local deployment_name="$1"

  awk -v wanted="$deployment_name" '
    function emit_if_match() {
      if (kind == "Deployment" && resource_name == wanted) {
        printf "%s", document
        matches++
      }
    }
    function reset_document() {
      document = ""
      kind = ""
      resource_name = ""
      in_metadata = 0
    }
    BEGIN {
      reset_document()
    }
    /^---$/ {
      emit_if_match()
      reset_document()
      next
    }
    {
      document = document $0 ORS
    }
    /^kind:[[:space:]]+/ {
      kind = $2
    }
    /^metadata:$/ {
      in_metadata = 1
      next
    }
    in_metadata && /^  name:[[:space:]]+/ {
      resource_name = $2
      in_metadata = 0
    }
    END {
      emit_if_match()
      if (matches != 1) {
        exit 1
      }
    }
  '
}

count_exact_line() {
  local document="$1"
  local line="$2"
  grep -Fxc "$line" <<< "$document" || true
}

assert_api_resources() {
  local rendered="$1"
  local deployment_name="$2"
  local deployment

  if ! deployment="$(deployment_document "$deployment_name" <<< "$rendered")"; then
    printf 'expected exactly one Deployment named %s\n' "$deployment_name" >&2
    return 1
  fi

  local expectation
  for expectation in \
    '              cpu: 500m' \
    '              cpu: 50m' \
    '              memory: 256Mi' \
    '              memory: 64Mi'; do
    if [[ "$(count_exact_line "$deployment" "$expectation")" -ne 1 ]]; then
      printf 'Deployment %s does not contain exactly one expected resource line: %s\n' \
        "$deployment_name" "$expectation" >&2
      return 1
    fi
  done
}

rendered="$(helm template bedoux "$chart_dir" \
  -f "$chart_dir/values-aws.yaml" \
  --set canary.enabled=true)"
assert_api_resources "$rendered" api
assert_api_resources "$rendered" api-canary

# Prove the assertion is sensitive to a real inheritance break, not merely to the
# presence of resource-looking text elsewhere in the multi-document render.
#
# M2/ADR 0024 moved the pod spec into the shared bedoux.apiPodSpec helper, so stable and
# canary now render from the same text. The break must therefore be asymmetric: editing
# the shared helper symmetrically would change both sides together and prove nothing.
fixture_dir="$(mktemp -d /tmp/bedoux-p14-resource-test.XXXXXX)"
cp -a "$chart_dir" "$fixture_dir/bedoux"
sed -i \
  's#{{- toYaml $api.resources | nindent 6 }}#{{- toYaml (ternary $api.resources $ctx.Values.web.resources (eq .app "api")) | nindent 6 }}#' \
  "$fixture_dir/bedoux/templates/_helpers.tpl"
grep -Fq '(ternary $api.resources $ctx.Values.web.resources (eq .app "api"))' \
  "$fixture_dir/bedoux/templates/_helpers.tpl"

divergent_render="$(helm template bedoux "$fixture_dir/bedoux" \
  -f "$fixture_dir/bedoux/values-aws.yaml" \
  --set canary.enabled=true)"
if assert_api_resources "$divergent_render" api-canary >/dev/null 2>&1; then
  printf '%s\n' 'resource assertion accepted a deliberately divergent api-canary' >&2
  exit 1
fi

printf '%s\n' 'P14.1 stable/canary resource assertions and divergent fixture OK'
