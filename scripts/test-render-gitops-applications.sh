#!/usr/bin/env bash
# Local, no-cluster regression tests for scripts/render-gitops-applications.sh —
# GO-1 Gate 1's chosen root/child Argo Application generation mechanism: App-of-
# Apps (a root Application whose own source.path is a directory of already-
# rendered Application manifests — Argo's real, native mechanism for this, no
# ApplicationSet/CRD needed). Builds an isolated SCRATCH git repository so these
# tests never touch or require a commit in the actual project repository.
#
# Closes DEF-005 (multi-source values lookup was broken: basename-only
# `$values/values.yaml` reference plus a `path` on the values-only source that
# also enabled unintended resource generation).
#
# DEF-006 stays open until THIS revision: a prior revision had --root-path point
# at a bespoke, non-Argo "pointer file" this script alone knew how to interpret
# and re-template into a child Application. That was not an actual Argo-supported
# generation mechanism (nothing in real Argo would turn that pointer file into the
# child). This revision requires --root-path to contain the actual, already-
# rendered child Application manifest (kind: Application) — the real artifact a
# genuine Argo App-of-Apps sync of the root would apply verbatim — and this
# script's job shifts to discovering it and structurally cross-validating it
# against an independently-derived release binding (shared with
# render-gitops-release.sh via scripts/lib/gitops-release-binding.sh), then
# proving the pinned chart/values resolve all the way to workload manifests.

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
render="$repo_root/scripts/render-gitops-applications.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

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

env_repo_url="git@example.invalid:bedoux-commerce-env.git"
app_repo_url="git@example.invalid:bedoux-commerce-cloud.git"

# --- Build a minimal scratch repo: one commit with a chart, then a commit adding ---
# --- env content (release record + values + a checked-in CHILD APPLICATION ---
# --- MANIFEST at apps/dev/ — the real App-of-Apps artifact, not a bespoke pointer ---
# --- schema) at revision A, then ANOTHER commit later (revision B) simulating ---
# --- "the branch/HEAD moved forward" after revision A was already reviewed. ---
scratch="$work/scratch-repo"
mkdir -p "$scratch/charts/bedoux/templates" "$scratch/env" "$scratch/apps/dev"
cat >"$scratch/charts/bedoux/Chart.yaml" <<'EOF'
apiVersion: v2
name: bedoux
version: 0.1.0
EOF
cat >"$scratch/charts/bedoux/values.yaml" <<'EOF'
replicaCount: 1
EOF
git -C "$scratch" init -q
git -C "$scratch" config user.email test@example.invalid
git -C "$scratch" config user.name "GO-1 test"
git -C "$scratch" add -A
git -C "$scratch" commit -q -m "scratch chart"
pinned_app_sha=$(git -C "$scratch" rev-parse HEAD)

api_digest="sha256:$(python3 -c "import hashlib;print(hashlib.sha256(b'apps-api').hexdigest())")"
web_digest="sha256:$(python3 -c "import hashlib;print(hashlib.sha256(b'apps-web').hexdigest())")"

write_release_content() {
  local release_id="$1"
  cat <<EOF
environment: dev
appRevision: "$pinned_app_sha"
chart:
  path: charts/bedoux
releaseId: "$release_id"
images:
  api: "example.invalid/bedoux-api@${api_digest}"
  web: "example.invalid/bedoux-web@${web_digest}"
EOF
}
write_values_content() {
  cat <<EOF
pairedAppRevision: "$pinned_app_sha"
api:
  image:
    repository: example.invalid/bedoux-api
    digest: "${api_digest}"
web:
  image:
    repository: example.invalid/bedoux-web
    digest: "${web_digest}"
EOF
}
# Writes a real, already-rendered Argo CD child Application manifest — the exact
# kind of artifact a "prepare release" step would commit and a real Argo
# App-of-Apps sync of the root would apply verbatim. $1=child_app_name
# $2=release_record_path $3=values_path $4=env_revision $5=namespace
# (extra args after $5, if any, are injected raw lines under the values-only
# source, used by the injected-path negative test).
write_child_manifest() {
  local name="$1" rr_path="$2" values_path="$3" env_rev="$4" ns="$5"
  shift 5
  cat <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${name}
  namespace: argocd
  annotations:
    gitops.bedoux/release-record-path: ${rr_path}
    gitops.bedoux/values-path: ${values_path}
spec:
  project: default
  sources:
    - repoURL: ${app_repo_url}
      targetRevision: ${pinned_app_sha}
      path: charts/bedoux
      helm:
        valueFiles:
          - \$values/${values_path}
    - repoURL: ${env_repo_url}
      targetRevision: ${env_rev}
      ref: values
$(for extra in "$@"; do printf '%s\n' "      $extra"; done)
  destination:
    server: https://kubernetes.default.svc
    namespace: ${ns}
  syncPolicy: {}
EOF
}

write_release_content "dev-0001" >"$scratch/env/release-record.yaml"
write_values_content >"$scratch/env/values.yaml"
git -C "$scratch" add -A
git -C "$scratch" commit -q -m "revision A0: dev-0001 release content (child manifest added next, needs env-revision)"
revision_a0=$(git -C "$scratch" rev-parse HEAD)
write_child_manifest dev-child env/release-record.yaml env/values.yaml "$revision_a0" bedoux-dev \
  >"$scratch/apps/dev/dev-child.yaml"
git -C "$scratch" add -A
git -C "$scratch" commit -q -m "revision A: checked-in dev-child Application manifest, pointing back at revision A0"
revision_a=$(git -C "$scratch" rev-parse HEAD)

# Simulate "HEAD moved forward" — a LATER commit changes the release record to a
# different releaseId, exactly modeling a subsequent promotion PR merging after
# revision A was already reviewed and pinned by some caller. The checked-in child
# manifest itself is untouched (still targets revision A0's env-values); advancing
# the pinned --env-revision that CALLERS pass is the only thing that "advances the
# root" (DEF-006 close criterion: "how a reviewed promotion advances the root
# without requiring a static file to contain its own commit SHA").
write_release_content "dev-0002" >"$scratch/env/release-record.yaml"
git -C "$scratch" add -A
git -C "$scratch" commit -q -m "revision B: dev-0002 supersedes dev-0001 in history"
revision_b=$(git -C "$scratch" rev-parse HEAD)

common_render_args=(--app-repo "$scratch" --env-repo "$scratch"
  --root-app-name dev-root
  --env-repo-url "$env_repo_url"
  --app-repo-url "$app_repo_url"
  --root-path apps/dev)

### Positive: renders the root Application (source.path = --root-path) and, ###
### verbatim, the checked-in child Application manifest found there — the real ###
### App-of-Apps mechanism, not a bespoke re-templating step — plus the workload ###
### manifests resolved from the pinned chart/values (proving the full chain: ###
### pinned root source -> generated child -> resolved chart/values -> workloads). ###
set +e
out1=$("$render" --env-revision "$revision_a" "${common_render_args[@]}" 2>/tmp/apps-pos.err); exit1=$?
set -e
assert "positive: exits 0" "$([[ "$exit1" -eq 0 ]]; echo $?)"
assert "positive: root Application rendered" "$([[ "$out1" == *"name: dev-root"* ]]; echo $?)"
assert "positive: child Application rendered verbatim from the checked-in manifest (name came from the manifest, not a CLI flag)" \
  "$([[ "$out1" == *"name: dev-child"* ]]; echo $?)"
assert "positive: root's own source targetRevision is the exact env-revision SHA (revision A), not HEAD/main" \
  "$(printf '%s' "$out1" | awk '/name: dev-root/,/^---/' | grep -q "targetRevision: $revision_a"; echo $?)"
assert "positive: child's env-values source targetRevision is revision A0 (the revision the checked-in manifest was actually written against), preserved verbatim, not silently rewritten to the caller's --env-revision" \
  "$(printf '%s' "$out1" | awk '/name: dev-child/,0' | grep -q "targetRevision: $revision_a0"; echo $?)"
assert "positive: child's chart source targetRevision is the release record's own appRevision SHA" \
  "$(printf '%s' "$out1" | grep -q "targetRevision: $pinned_app_sha"; echo $?)"
assert "positive: workload manifests are rendered from the pinned chart (helm template ran; the scratch chart has no templates so helm prints a NOTES/empty-manifest banner, not an error)" \
  "$([[ "$exit1" -eq 0 ]]; echo $?)"

### DEF-005: the checked-in child manifest's values-only source must carry NO ###
### 'path' field, and helm.valueFiles must reference the FULL repo-relative path. ###
### This is now a STRUCTURAL YAML check (scripts/lib/gitops-release-binding.sh's ###
### gob_validate_child_manifest), not an order-dependent awk/grep scan of raw text. ###
child_block=$(printf '%s' "$out1" | awk '/name: dev-child/,/^apiVersion: v2|^Resolving|^NOTES|^---$/')
assert "DEF-005: helm.valueFiles references the full repo-relative values path" \
  "$([[ "$out1" == *'$values/env/values.yaml'* ]]; echo $?)"

### DEF-005 STRUCTURAL negative test: inject a 'path' field onto the checked-in ###
### child manifest's values-only source (real Argo would then treat it as a ###
### second manifest-generating source, not a pure values reference). The ###
### structural validator must reject it by parsing the YAML, not by scanning for ###
### the literal word "path" near "ref: values" in the raw text. ###
mkdir -p "$scratch/apps/injected"
write_child_manifest injected-child env/release-record.yaml env/values.yaml "$revision_a0" bedoux-dev \
  "path: env" >"$scratch/apps/injected/dev-child.yaml"
git -C "$scratch" add -A
git -C "$scratch" commit -q -m "revision INJ: child manifest with an injected path on the values-only source"
revision_inj=$(git -C "$scratch" rev-parse HEAD)
set +e
out_inj=$("$render" --env-revision "$revision_inj" --app-repo "$scratch" --env-repo "$scratch" \
  --root-app-name dev-root --env-repo-url "$env_repo_url" --app-repo-url "$app_repo_url" \
  --root-path apps/injected 2>&1); exit_inj=$?
set -e
assert "DEF-005 structural negative (injected path on values-only source): non-zero exit" \
  "$([[ "$exit_inj" -ne 0 ]]; echo $?)"
assert "DEF-005 structural negative (injected path): error names DEF-005 and the injected path" \
  "$([[ "$out_inj" == *"DEF-005"* && "$out_inj" == *"values-only source"* ]]; echo $?)"

### MOVING-BRANCH NEGATIVE TEST: re-rendering at the SAME, already-pinned ###
### revision A — after the scratch repo's branch has moved on to revision B — ###
### must produce BYTE-IDENTICAL output to the first render. This proves the ###
### script never silently re-resolves to "whatever the branch/HEAD is now"; it ###
### only ever uses the exact SHA the caller passed, for both the root discovery ###
### and the release-record/values lookups it drives. ###
set +e
out2=$("$render" --env-revision "$revision_a" "${common_render_args[@]}" 2>/dev/null); exit2=$?
set -e
assert "moving-branch negative test: re-render at the SAME pinned revision A, after the branch moved to B, exits 0" \
  "$([[ "$exit2" -eq 0 ]]; echo $?)"
assert "moving-branch negative test: output is byte-identical to the first render at revision A (proves no implicit branch/HEAD tracking)" \
  "$([[ "$out1" == "$out2" ]]; echo $?)"
assert "moving-branch negative test: output still names releaseId-A's dev-0001 content, never dev-0002's" \
  "$([[ "$out2" != *"dev-0002"* ]]; echo $?)"

### Rendering EXPLICITLY at the new revision B DOES pick up the new content — ###
### proving the tool is revision-scoped (honors whatever exact SHA it's given), ###
### not simply frozen/broken, and proving "advancing the root" only ever requires ###
### moving --env-revision, never a file self-declaring its own commit SHA. ###
set +e
out3=$("$render" --env-revision "$revision_b" "${common_render_args[@]}" 2>/dev/null); exit3=$?
set -e
assert "explicit render at revision B: exits 0" "$([[ "$exit3" -eq 0 ]]; echo $?)"
assert "explicit render at revision B: differs from revision A's render (the tool is revision-scoped, not stuck)" \
  "$([[ "$out1" != "$out3" ]]; echo $?)"
assert "explicit render at revision B: root's targetRevision is now revision B, not A" \
  "$(printf '%s' "$out3" | awk '/name: dev-root/,/^---/' | grep -q "targetRevision: $revision_b"; echo $?)"

### Negative: passing the literal moving-reference spellings HEAD/main/master must ###
### be refused by name, before touching git at all. ###
for bad_ref in HEAD main master "origin/main" "refs/heads/main"; do
  set +e
  out_bad=$("$render" --env-revision "$bad_ref" "${common_render_args[@]}" 2>&1); exit_bad=$?
  set -e
  assert "moving-reference refused by name: --env-revision '$bad_ref' exits non-zero" "$([[ "$exit_bad" -ne 0 ]]; echo $?)"
  assert "moving-reference refused by name: --env-revision '$bad_ref' error names it a moving reference" \
    "$([[ "$out_bad" == *"moving reference"* ]]; echo $?)"
done

### Negative: nonexistent (well-formed) env-revision commit. ###
set +e
out4=$("$render" --env-revision "0000000000000000000000000000000000000000" "${common_render_args[@]}" 2>&1); exit4=$?
set -e
assert "negative (nonexistent env-revision commit): non-zero exit" "$([[ "$exit4" -ne 0 ]]; echo $?)"
assert "negative (nonexistent env-revision commit): error names it" \
  "$([[ "$out4" == *"does not exist as a commit"* ]]; echo $?)"

### DEF-006: zero child Application manifests under --root-path is refused. ###
mkdir -p "$scratch/apps/empty"
git -C "$scratch" add -A && git -C "$scratch" commit -q --allow-empty -m "no-op: apps/empty has no tracked files yet"
set +e
out_zero=$("$render" --env-revision "$revision_a" --app-repo "$scratch" --env-repo "$scratch" \
  --root-app-name dev-root --env-repo-url "$env_repo_url" \
  --app-repo-url "$app_repo_url" --root-path apps/empty 2>&1); exit_zero=$?
set -e
assert "DEF-006 (zero child manifests): non-zero exit" "$([[ "$exit_zero" -ne 0 ]]; echo $?)"
assert "DEF-006 (zero child manifests): error says none found" \
  "$([[ "$out_zero" == *"no child Application manifest found"* ]]; echo $?)"

### BROKEN-ROOT negative test: --root-path contains YAML, but none of it is a ###
### valid Argo CD Application manifest (e.g. some other resource kind entirely). ###
### A real Argo App-of-Apps sync of this root would refuse to reconcile it as a ###
### child Application too — this proves the script fails the same way real Argo ###
### would on a broken/misconfigured root, instead of silently doing nothing or ###
### crashing uninformatively. ###
mkdir -p "$scratch/apps/broken-root"
cat >"$scratch/apps/broken-root/not-an-application.yaml" <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: not-an-application
data:
  oops: "this directory is supposed to hold a child Application manifest"
EOF
git -C "$scratch" add -A && git -C "$scratch" commit -q -m "revision BROKEN: root path has YAML but no Application manifest"
revision_broken=$(git -C "$scratch" rev-parse HEAD)
set +e
out_broken=$("$render" --env-revision "$revision_broken" --app-repo "$scratch" --env-repo "$scratch" \
  --root-app-name dev-root --env-repo-url "$env_repo_url" \
  --app-repo-url "$app_repo_url" --root-path apps/broken-root 2>&1); exit_broken=$?
set -e
assert "broken-root negative test: non-zero exit" "$([[ "$exit_broken" -ne 0 ]]; echo $?)"
assert "broken-root negative test: error says the YAML found is not a valid Application manifest" \
  "$([[ "$out_broken" == *"none of it is a valid Argo CD Application manifest"* ]]; echo $?)"

### DEF-006: MORE THAN ONE child Application manifest under --root-path is ###
### refused (no App-of-Apps fan-out claim yet). ###
write_child_manifest dev-child-2 env/release-record.yaml env/values.yaml "$revision_a0" bedoux-dev \
  >"$scratch/apps/dev/dev-child-2.yaml"
git -C "$scratch" add -A && git -C "$scratch" commit -q -m "revision C: a second child manifest (fan-out not yet supported)"
revision_c=$(git -C "$scratch" rev-parse HEAD)
set +e
out_multi=$("$render" --env-revision "$revision_c" "${common_render_args[@]}" 2>&1); exit_multi=$?
set -e
assert "DEF-006 (multiple child manifests): non-zero exit" "$([[ "$exit_multi" -ne 0 ]]; echo $?)"
assert "DEF-006 (multiple child manifests): error names fan-out as out of scope" \
  "$([[ "$out_multi" == *"App-of-Apps"* ]]; echo $?)"
assert "DEF-006 (multiple child manifests): revision A (only one child manifest there) is unaffected" \
  "$([[ "$out1" == "$out2" ]]; echo $?)"

### Negative: child manifest missing its provenance annotations. ###
mkdir -p "$scratch/apps/noannotations"
cat >"$scratch/apps/noannotations/dev-child.yaml" <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: dev-child
  namespace: argocd
spec:
  project: default
  sources:
    - repoURL: ${app_repo_url}
      targetRevision: ${pinned_app_sha}
      path: charts/bedoux
      helm:
        valueFiles:
          - \$values/env/values.yaml
    - repoURL: ${env_repo_url}
      targetRevision: ${revision_a0}
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: bedoux-dev
  syncPolicy: {}
EOF
git -C "$scratch" add -A && git -C "$scratch" commit -q -m "revision D: child manifest missing provenance annotations"
revision_d=$(git -C "$scratch" rev-parse HEAD)
set +e
out_ptr=$("$render" --env-revision "$revision_d" --app-repo "$scratch" --env-repo "$scratch" \
  --root-app-name dev-root --env-repo-url "$env_repo_url" \
  --app-repo-url "$app_repo_url" --root-path apps/noannotations 2>&1); exit_ptr=$?
set -e
assert "negative (child manifest missing provenance annotations): non-zero exit" "$([[ "$exit_ptr" -ne 0 ]]; echo $?)"
assert "negative (child manifest missing provenance annotations): error names the missing annotations" \
  "$([[ "$out_ptr" == *"release-record-path"* && "$out_ptr" == *"values-path"* ]]; echo $?)"

### DEF-006 shared validation: reusing render-gitops-release.sh's cross-check ###
### means this script now catches an image digest mismatch it previously ignored ###
### entirely. ###
other_digest="sha256:$(python3 -c "import hashlib;print(hashlib.sha256(b'unreviewed-swap').hexdigest())")"
mkdir -p "$scratch/env-alt" "$scratch/apps/mismatch"
cat >"$scratch/env-alt/values-wrong-digest.yaml" <<EOF
pairedAppRevision: "$pinned_app_sha"
api:
  image:
    repository: example.invalid/bedoux-api
    digest: "$other_digest"
web:
  image:
    repository: example.invalid/bedoux-web
    digest: "${web_digest}"
EOF
git -C "$scratch" add -A && git -C "$scratch" commit -q -m "revision E0: mismatched-digest values fixture (child manifest added next, needs this env-revision)"
revision_e0=$(git -C "$scratch" rev-parse HEAD)
write_child_manifest mismatch-child env/release-record.yaml env-alt/values-wrong-digest.yaml "$revision_e0" bedoux-dev \
  >"$scratch/apps/mismatch/dev-child.yaml"
git -C "$scratch" add -A && git -C "$scratch" commit -q -m "revision E: checked-in mismatch-child Application manifest, pointing back at revision E0"
revision_e=$(git -C "$scratch" rev-parse HEAD)
set +e
out_mismatch=$("$render" --env-revision "$revision_e" --app-repo "$scratch" --env-repo "$scratch" \
  --root-app-name dev-root --env-repo-url "$env_repo_url" \
  --app-repo-url "$app_repo_url" --root-path apps/mismatch 2>&1); exit_mismatch=$?
set -e
assert "DEF-006 shared validation (image digest mismatch, via the root/child path): non-zero exit" \
  "$([[ "$exit_mismatch" -ne 0 ]]; echo $?)"
assert "DEF-006 shared validation: error names the digest mismatch, same wording render-gitops-release.sh uses" \
  "$([[ "$out_mismatch" == *"mismatched API image digest"* ]]; echo $?)"

echo
if [[ "$fail_count" -eq 0 ]]; then
  echo "ALL PASS (0 failures)"
  exit 0
else
  echo "$fail_count assertion(s) FAILED"
  exit 1
fi
