#!/usr/bin/env bash
# Local, no-cluster regression tests for scripts/render-gitops-release.sh's full
# root/child binding contract. Builds an isolated SCRATCH git repository (a minimal
# real Helm chart + release record + values) so these tests never touch or require
# a commit in the actual project repository — nothing here depends on this
# session's uncommitted work landing in real history.
#
# Reproduces the defects from Codex's second GO-1 review (docs/PROGRESS.md session
# log 2026-09-09T13:29:08-06:00): a values file with the correct pairedAppRevision
# but a DIFFERENT, unreviewed image digest previously rendered successfully (should
# refuse); pairedAppRevision was optional (should be mandatory); nothing pinned or
# verified an environment revision for the values/release-record source (should be
# mandatory and verified).

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
render="$repo_root/scripts/render-gitops-release.sh"

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

# --- Build a minimal, real, self-contained scratch chart + env content. ---
scratch="$work/scratch-repo"
mkdir -p "$scratch/charts/bedoux/templates" "$scratch/env"
cat >"$scratch/charts/bedoux/Chart.yaml" <<'EOF'
apiVersion: v2
name: bedoux
version: 0.1.0
EOF
cat >"$scratch/charts/bedoux/values.yaml" <<'EOF'
api:
  image:
    repository: example.invalid/bedoux-api
    tag: base
    digest: ""
web:
  image:
    repository: example.invalid/bedoux-web
    tag: base
    digest: ""
EOF
cat >"$scratch/charts/bedoux/templates/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bedoux-api
spec:
  template:
    spec:
      containers:
        - name: api
          image: "{{ .Values.api.image.repository }}@{{ .Values.api.image.digest }}"
EOF

git -C "$scratch" init -q
git -C "$scratch" config user.email test@example.invalid
git -C "$scratch" config user.name "GO-1 test"
git -C "$scratch" add -A
git -C "$scratch" commit -q -m "scratch chart"
pinned_sha=$(git -C "$scratch" rev-parse HEAD)

api_digest="sha256:$(python3 -c "import hashlib;print(hashlib.sha256(b'scratch-api').hexdigest())")"
web_digest="sha256:$(python3 -c "import hashlib;print(hashlib.sha256(b'scratch-web').hexdigest())")"
other_digest="sha256:$(python3 -c "import hashlib;print(hashlib.sha256(b'unreviewed-swap').hexdigest())")"

# appRevision is pinned_sha (the chart's own commit) and stays that way — the chart
# is never touched again, so there is no need to re-pin it to a later commit, and
# no self-referential "make this file declare the hash of the commit that contains
# it" problem (an earlier version of this test hit exactly that circularity for
# envRevision, and separately, unintentionally, for appRevision too, by trying to
# rewrite these files to reference their own final commit after the fact).
cat >"$scratch/env/release-record.yaml" <<EOF
environment: dev
appRevision: "$pinned_sha"
chart:
  path: charts/bedoux
releaseId: "scratch-0001"
images:
  api: "example.invalid/bedoux-api@${api_digest}"
  web: "example.invalid/bedoux-web@${web_digest}"
EOF
cat >"$scratch/env/values.yaml" <<EOF
pairedAppRevision: "$pinned_sha"
api:
  image:
    repository: example.invalid/bedoux-api
    tag: "scratch-0001"
    digest: "$api_digest"
web:
  image:
    repository: example.invalid/bedoux-web
    tag: "scratch-0001"
    digest: "$web_digest"
EOF
git -C "$scratch" add -A
git -C "$scratch" commit -q -m "scratch env content"
final_sha=$(git -C "$scratch" rev-parse HEAD)

run_render() {
  "$render" --app-repo "$scratch" --env-repo "$scratch" \
    --env-revision "$final_sha" --release-record-path env/release-record.yaml \
    --values-path env/values.yaml "$@"
}

### Positive: everything consistent, renders successfully. ###
set +e
out1=$(run_render 2>/tmp/render-pos.err); exit1=$?
set -e
assert "positive: consistent root/child render exits 0" "$([[ "$exit1" -eq 0 ]]; echo $?)"
assert "positive: rendered output contains the pinned api digest" \
  "$([[ "$out1" == *"$api_digest"* ]]; echo $?)"

### Working-tree independence: dirty the SCRATCH repo's own tracked file (never ###
### the real project repo) and prove the pinned render is unaffected. ###
cp "$scratch/charts/bedoux/values.yaml" "$work/values.yaml.orig"
sed -i 's/base/DIRTY-SHOULD-NOT-APPEAR/' "$scratch/charts/bedoux/values.yaml"
set +e
out2=$(run_render 2>/dev/null); exit2=$?
set -e
cp "$work/values.yaml.orig" "$scratch/charts/bedoux/values.yaml"
assert "working-tree independence: dirty-scratch-tree render still exits 0" "$([[ "$exit2" -eq 0 ]]; echo $?)"
assert "working-tree independence: dirty edit does not leak into the pinned render" \
  "$([[ "$out2" != *"DIRTY-SHOULD-NOT-APPEAR"* ]]; echo $?)"
assert "working-tree independence: dirty-tree render byte-identical to clean-tree render" \
  "$([[ "$out1" == "$out2" ]]; echo $?)"

### Negative: mismatched API image digest — correct pairedAppRevision, wrong digest. ###
cat >"$work/values-wrong-digest.yaml" <<EOF
pairedAppRevision: "$pinned_sha"
api:
  image:
    repository: example.invalid/bedoux-api
    tag: "unreviewed"
    digest: "$other_digest"
web:
  image:
    repository: example.invalid/bedoux-web
    tag: "scratch-0001"
    digest: "$web_digest"
EOF
mkdir -p "$scratch/env-alt"
cp "$work/values-wrong-digest.yaml" "$scratch/env-alt/values-wrong-digest.yaml"
git -C "$scratch" add -A && git -C "$scratch" commit -q -m "add mismatched-digest fixture"
alt_sha=$(git -C "$scratch" rev-parse HEAD)
set +e
out3=$("$render" --app-repo "$scratch" --env-repo "$scratch" --env-revision "$alt_sha" \
  --release-record-path env/release-record.yaml --values-path env-alt/values-wrong-digest.yaml 2>&1)
exit3=$?
set -e
assert "REPRO (mismatched image digest, correct pairedAppRevision): non-zero exit" "$([[ "$exit3" -ne 0 ]]; echo $?)"
assert "mismatched image digest: error names the mismatch specifically" \
  "$([[ "$out3" == *"mismatched API image digest"* || "$out3" == *"mismatched web image digest"* ]]; echo $?)"

### Negative: pairedAppRevision missing entirely — must now be refused, not skipped. ###
cat >"$scratch/env-alt/values-no-paired.yaml" <<EOF
api:
  image:
    repository: example.invalid/bedoux-api
    tag: "scratch-0001"
    digest: "$api_digest"
web:
  image:
    repository: example.invalid/bedoux-web
    tag: "scratch-0001"
    digest: "$web_digest"
EOF
git -C "$scratch" add -A && git -C "$scratch" commit -q -m "add missing-pairedAppRevision fixture"
alt2_sha=$(git -C "$scratch" rev-parse HEAD)
set +e
out4=$("$render" --app-repo "$scratch" --env-repo "$scratch" --env-revision "$alt2_sha" \
  --release-record-path env/release-record.yaml --values-path env-alt/values-no-paired.yaml 2>&1)
exit4=$?
set -e
assert "pairedAppRevision now mandatory: missing field is refused" "$([[ "$exit4" -ne 0 ]]; echo $?)"
assert "mandatory pairedAppRevision: error says it is mandatory" \
  "$([[ "$out4" == *"mandatory, not optional"* ]]; echo $?)"

### Negative: pairedAppRevision PRESENT but wrong (distinct from missing above). ###
cat >"$scratch/env-alt/values-wrong-paired.yaml" <<EOF
pairedAppRevision: "0000000000000000000000000000000000000000"
api:
  image:
    repository: example.invalid/bedoux-api
    tag: "scratch-0001"
    digest: "$api_digest"
web:
  image:
    repository: example.invalid/bedoux-web
    tag: "scratch-0001"
    digest: "$web_digest"
EOF
git -C "$scratch" add -A && git -C "$scratch" commit -q -m "add wrong-pairedAppRevision fixture"
alt4_sha=$(git -C "$scratch" rev-parse HEAD)
set +e
out8=$("$render" --app-repo "$scratch" --env-repo "$scratch" --env-revision "$alt4_sha" \
  --release-record-path env/release-record.yaml --values-path env-alt/values-wrong-paired.yaml 2>&1)
exit8=$?
set -e
assert "pairedAppRevision present but wrong: non-zero exit" "$([[ "$exit8" -ne 0 ]]; echo $?)"
assert "pairedAppRevision present but wrong: error names mixed-revision mismatch" \
  "$([[ "$out8" == *"mixed-revision mismatch"* ]]; echo $?)"

### Negative (Codex's third-review exact counterexample): CORRECT digest, but a ###
### DIFFERENT repository — reproduced with a synthetic env commit exactly like the ###
### review's own (api digest kept, repository changed from ###
### example.invalid/bedoux-api to example.invalid/wrong-repository). Must refuse: ###
### a matching digest never substitutes for a verified repository/registry binding. ###
cat >"$scratch/env-alt/values-wrong-repository.yaml" <<EOF
pairedAppRevision: "$pinned_sha"
api:
  image:
    repository: example.invalid/wrong-repository
    tag: "scratch-0001"
    digest: "$api_digest"
web:
  image:
    repository: example.invalid/bedoux-web
    tag: "scratch-0001"
    digest: "$web_digest"
EOF
git -C "$scratch" add -A && git -C "$scratch" commit -q -m "add wrong-repository fixture"
alt5_sha=$(git -C "$scratch" rev-parse HEAD)
set +e
out9=$("$render" --app-repo "$scratch" --env-repo "$scratch" --env-revision "$alt5_sha" \
  --release-record-path env/release-record.yaml --values-path env-alt/values-wrong-repository.yaml 2>&1)
exit9=$?
set -e
assert "REPRO (mismatched image repository, correct digest): non-zero exit" "$([[ "$exit9" -ne 0 ]]; echo $?)"
assert "mismatched image repository: error names the repository mismatch specifically, not the digest" \
  "$([[ "$out9" == *"mismatched API image repository"* ]]; echo $?)"

### Negative/positive pair proving --env-revision is genuinely pinned and honored,
### not accepted-and-ignored: request the SAME release-record-path/values-path but
### at pinned_sha (the FIRST scratch commit, chart-only — env/ does not exist yet
### at that point in history). Must refuse because the paths don't exist THERE,
### even though they exist at final_sha. This is the actual env-revision gate:
### changing --env-revision changes which commit's content is read.
set +e
out5=$("$render" --app-repo "$scratch" --env-repo "$scratch" --env-revision "$pinned_sha" \
  --release-record-path env/release-record.yaml --values-path env/values.yaml 2>&1)
exit5=$?
set -e
assert "env-revision is genuinely honored: same paths at an EARLIER commit (before env/ existed) are refused" \
  "$([[ "$exit5" -ne 0 ]]; echo $?)"
assert "env-revision genuinely honored: error names the specific earlier commit and path, proving it actually read at that revision" \
  "$([[ "$out5" == *"$pinned_sha"* && "$out5" == *"env/release-record.yaml"* ]]; echo $?)"

### Negative: invalid --env-revision syntax refused before touching git/helm. ###
set +e
out6=$("$render" --app-repo "$scratch" --env-repo "$scratch" --env-revision "not-a-sha" \
  --release-record-path env/release-record.yaml --values-path env/values.yaml 2>&1)
exit6=$?
set -e
assert "negative (invalid env-revision syntax): non-zero exit" "$([[ "$exit6" -ne 0 ]]; echo $?)"
assert "negative (invalid env-revision syntax): refuses before rendering" \
  "$([[ "$out6" != *"apiVersion:"* ]]; echo $?)"

### Negative: nonexistent (well-formed) env-revision commit. ###
set +e
out7=$("$render" --app-repo "$scratch" --env-repo "$scratch" \
  --env-revision "0000000000000000000000000000000000000000" \
  --release-record-path env/release-record.yaml --values-path env/values.yaml 2>&1)
exit7=$?
set -e
assert "negative (nonexistent env-revision commit): non-zero exit" "$([[ "$exit7" -ne 0 ]]; echo $?)"
assert "negative (nonexistent env-revision commit): error names it" \
  "$([[ "$out7" == *"does not exist as a commit"* ]]; echo $?)"

echo
if [[ "$fail_count" -eq 0 ]]; then
  echo "ALL PASS (0 failures)"
  exit 0
else
  echo "$fail_count assertion(s) FAILED"
  exit 1
fi
