#!/usr/bin/env bash
# Local regression tests for the charts/bedoux changes GO-MVP made to
# migration-job.yaml/postgres.yaml/api-serviceaccount.yaml/api.yaml/web.yaml/
# ingress.yaml (migration.gitopsMode + Argo sync-wave annotations). Uses real
# `helm template` — no cluster contact. Proves: the legacy Helm CLI path is
# unaffected in substance (only new, inert argocd.argoproj.io/* annotations
# appear — no helm.sh/hook change, no behavior change for `helm install`/
# `upgrade`); gitopsMode emits a plain, non-hook, sync-wave "0" Job named after
# the exact image tag (so two different tags never collide, and no
# Replace=true/immutable-field workaround is needed — Codex's GO-MVP review,
# DEF-012); wave "-1" covers Postgres/Secret/ServiceAccount and wave "1" covers
# api/web/Ingress so the Ingress objects' perpetual "no controller" health can
# never block wave 1 from applying.

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
chart="$repo_root/charts/bedoux"

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

render() { helm template bedoux "$chart" "$@" 2>&1; }

### Legacy path (gitopsMode unset/false): helm.sh/hook annotations unchanged, ###
### name still keyed on .Release.Revision, no gitopsMode-only content present. ###
legacy=$(render)
assert "legacy: migration Job still uses helm.sh/hook post-install,pre-upgrade" \
  "$(grep -q 'helm.sh/hook": post-install,pre-upgrade' <<<"$legacy"; echo $?)"
assert "legacy: migration Job name still keyed on .Release.Revision (bedoux-migrate-1)" \
  "$(grep -q 'name: bedoux-migrate-1$' <<<"$legacy"; echo $?)"
assert "legacy: no gitopsMode-only Job name present" \
  "$([[ "$legacy" != *"bedoux-migrate-gitops"* ]]; echo $?)"
assert "legacy: postgres Secret/Deployment/Service still carry the inert sync-wave -1 annotation (added unconditionally, harmless to Helm CLI)" \
  "$(grep -c 'sync-wave: "-1"' <<<"$legacy" | grep -qE '^[4-9]|^[1-9][0-9]+$'; echo $?)"
assert "legacy: helm lint passes" "$(helm lint "$chart" >/dev/null 2>&1; echo $?)"

### gitopsMode=true: plain resource, wave 0, name keyed on the exact image tag. ###
gitops1=$(render --set migration.gitopsMode=true --set api.image.tag=mvp-aaaaaaaaaaaa)
assert "gitopsMode: no actual helm.sh/hook annotation key rendered (prose comments mentioning the phrase are fine)" \
  "$([[ "$gitops1" != *'"helm.sh/hook"'* ]]; echo $?)"
assert "gitopsMode: migration Job named after the exact image tag" \
  "$(grep -q 'name: bedoux-migrate-gitops-mvp-aaaaaaaaaaaa$' <<<"$gitops1"; echo $?)"
assert "gitopsMode: migration Job carries sync-wave 0" \
  "$(awk '/name: bedoux-migrate-gitops-mvp-aaaaaaaaaaaa$/,/^spec:/' <<<"$gitops1" | grep -q 'sync-wave: "0"'; echo $?)"
assert "gitopsMode: no Replace=true sync-option (removed — per-tag naming makes it unnecessary, and it did not reliably work anyway)" \
  "$([[ "$gitops1" != *"sync-options"* ]]; echo $?)"
assert "gitopsMode: api ServiceAccount carries sync-wave -1" \
  "$(awk '/kind: ServiceAccount/,/^---/' <<<"$gitops1" | grep -q 'sync-wave: "-1"'; echo $?)"
# GO-MVP-U1 fix: the previous version grabbed only the FIRST "kind: Deployment"
# block in the whole rendered manifest, which assumed postgres's Deployment
# happens to render before api's/web's — not guaranteed by Helm (object order
# depends on template file processing, which can differ across Helm versions/
# environments). Its `grep -B5 'name: postgres$'` fallback was equally
# unreliable: multiple rendered objects are named "postgres" (Secret, Service,
# Deployment), and "5 lines before this metadata.name" does not reliably land
# on THIS object's own annotations block. Live-reproduced in CI 2026-09-10 (a
# different Helm version than this dev host's): both matched the wrong object
# and the assertion false-FAILed even though the chart's actual annotation was
# correct. Fixed to scope by kind+name explicitly, the same robust pattern
# already used for the api/web Deployment checks below.
assert "gitopsMode: postgres Deployment carries sync-wave -1" \
  "$(awk '/^kind: Deployment/{d=1} d && /name: postgres$/{f=1} f{print} /^---/{if(f)exit}' <<<"$gitops1" | grep -q 'sync-wave: "-1"'; echo $?)"
assert "gitopsMode: api Deployment carries sync-wave 1" \
  "$(awk '/^kind: Deployment/{d=1} d && /name: api$/{f=1} f{print} /^---/{if(f)exit}' <<<"$gitops1" | grep -q 'sync-wave: "1"'; echo $?)"
assert "gitopsMode: web Deployment carries sync-wave 1" \
  "$(awk '/^kind: Deployment/{d=1} d && /name: web$/{f=1} f{print} /^---/{if(f)exit}' <<<"$gitops1" | grep -q 'sync-wave: "1"'; echo $?)"
assert "gitopsMode: Ingress bedoux-api carries sync-wave 1 (so its perpetual no-controller health can never block wave 1)" \
  "$(awk '/name: bedoux-api$/,/^---/' <<<"$gitops1" | grep -q 'sync-wave: "1"'; echo $?)"
assert "gitopsMode: Ingress bedoux-web carries sync-wave 1" \
  "$(awk '/name: bedoux-web$/,/^---/' <<<"$gitops1" | grep -q 'sync-wave: "1"'; echo $?)"
assert "gitopsMode: helm lint passes" "$(helm lint "$chart" --set migration.gitopsMode=true >/dev/null 2>&1; echo $?)"

### Two different image tags produce two DIFFERENT Job names — proves an update ###
### never collides with (or in-place-mutates) a prior release's Job. ###
gitops2=$(render --set migration.gitopsMode=true --set api.image.tag=mvp-bbbbbbbbbbbb)
assert "gitopsMode: a different image tag produces a genuinely different Job name" \
  "$([[ "$gitops1" != "$gitops2" ]] && grep -q 'bedoux-migrate-gitops-mvp-bbbbbbbbbbbb' <<<"$gitops2"; echo $?)"

### No replicas hardcoded in the chart's own defaults changing between these ###
### renders (the MVP's up.sh no longer overrides replicas at all — this proves ###
### the CHART's own default still governs and responds to an explicit override, ###
### i.e. a real values.yaml change would not be masked). ###
gitops3=$(render --set migration.gitopsMode=true --set web.replicas=3)
assert "an explicit web.replicas override is honored in the chart's own render (not masked by anything in the chart itself)" \
  "$(awk '/^kind: Deployment/{d=1} d && /name: web$/{f=1} f{print} /^---/{if(f)exit}' <<<"$gitops3" | grep -q 'replicas: 3'; echo $?)"

echo
if [[ "$fail_count" -eq 0 ]]; then
  echo "ALL PASS (0 failures)"
  exit 0
else
  echo "$fail_count assertion(s) FAILED"
  exit 1
fi
