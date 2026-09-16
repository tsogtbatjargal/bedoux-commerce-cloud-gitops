#!/usr/bin/env bash
# Local, no-cluster regression tests for scripts/gitops-suspend-reconciliation.sh's
# --execute path, using mock argocd/jq binaries on an isolated PATH. Reproduces the
# defects from both Codex GO-1 reviews (docs/PROGRESS.md session log entries
# 2026-09-09T11:03:16-06:00 and 2026-09-09T13:29:08-06:00): the script previously
# returned 0 with all-failing mocks, with a stuck "Terminating" phase, AND (second
# review) with a targeted jq failure during the final verification step even though
# the mocked Application genuinely still had automated: {} set. Contacts no real
# cluster or AWS resource.

set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gitops-suspend-reconciliation.sh"
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

mock_bin_dir() {
  local name="$1"
  local d="$work/$name"
  mkdir -p "$d"
  printf '%s' "$d"
}

run_with_mocks() {
  local bindir="$1"
  shift
  set +e
  last_output=$(PATH="$bindir:$PATH" "$script" "$@" --execute 2>&1)
  last_exit=$?
  set -e
}

common_args=(--context kind-test --root-app root-app --child-apps child-a,child-b
  --op-wait-timeout-seconds 1 --op-poll-seconds 1 --term-wait-timeout-seconds 1
  --verify-timeout-seconds 1 --cmd-timeout-seconds 2)

### Scenario 1: total failure — argocd and jq both always fail. ###
bindir1=$(mock_bin_dir scenario1)
cat >"$bindir1/argocd" <<'EOF'
#!/usr/bin/env bash
echo "mock argocd: simulated failure for: $*" >&2
exit 1
EOF
cat >"$bindir1/jq" <<'EOF'
#!/usr/bin/env bash
echo "mock jq: simulated failure" >&2
exit 1
EOF
chmod +x "$bindir1/argocd" "$bindir1/jq"

run_with_mocks "$bindir1" "${common_args[@]}"
assert "scenario 1 (total command failure): script exits non-zero" "$([[ "$last_exit" -ne 0 ]]; echo $?)"
assert "scenario 1: script never claims root/child verified suspended" \
  "$([[ "$last_output" != *"verified suspended"* ]]; echo $?)"
assert "scenario 1: script never touches a child (root failed first)" \
  "$([[ "$last_output" != *"(child)"* ]]; echo $?)"

### Scenario 2: operation stuck active forever, even after terminate-op. ###
bindir2=$(mock_bin_dir scenario2)
cat >"$bindir2/argocd" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "app" && "$2" == "get" ]]; then
  echo '{"kind":"Application","metadata":{"name":"'"$3"'"},"status":{"operationState":{"phase":"Terminating"}},"spec":{"syncPolicy":{}},"operation":null}'
  exit 0
fi
if [[ "$1" == "app" && "$2" == "set" ]]; then
  exit 0
fi
if [[ "$1" == "app" && "$2" == "terminate-op" ]]; then
  exit 0
fi
echo "mock argocd: unexpected args: $*" >&2
exit 1
EOF
chmod +x "$bindir2/argocd"

run_with_mocks "$bindir2" "${common_args[@]}"
assert "scenario 2 (stuck active phase, never clears): script exits non-zero" "$([[ "$last_exit" -ne 0 ]]; echo $?)"
assert "scenario 2: script never claims verified suspended" \
  "$([[ "$last_output" != *"verified suspended"* ]]; echo $?)"

### Scenario 3: fully healthy path. Root must disable automation BEFORE checking ###
### for operations, and be fully suspended before either child is touched. ###
bindir3=$(mock_bin_dir scenario3)
state3="$work/scenario3-state"
mkdir -p "$state3"
cat >"$bindir3/argocd" <<EOF
#!/usr/bin/env bash
app="\$3"
if [[ "\$1" == "app" && "\$2" == "get" ]]; then
  if [[ -f "$state3/\$app.suspended" ]]; then
    echo '{"kind":"Application","metadata":{"name":"'"\$app"'"},"status":{"operationState":{"phase":"None"}},"spec":{"syncPolicy":{}},"operation":null}'
  else
    echo '{"kind":"Application","metadata":{"name":"'"\$app"'"},"status":{"operationState":{"phase":"None"}},"spec":{"syncPolicy":{"automated":{}}},"operation":null}'
  fi
  exit 0
fi
if [[ "\$1" == "app" && "\$2" == "set" ]]; then
  echo "\$(date +%s%N) set \$app" >> "$state3/call-order.log"
  touch "$state3/\$app.suspended"
  exit 0
fi
echo "mock argocd: unexpected args: \$*" >&2
exit 1
EOF
chmod +x "$bindir3/argocd"

run_with_mocks "$bindir3" "${common_args[@]}"
assert "scenario 3 (healthy path): script exits 0" "$([[ "$last_exit" -eq 0 ]]; echo $?)"
assert "scenario 3: root-app verified suspended" \
  "$([[ "$last_output" == *"(root) root-app verified suspended"* ]]; echo $?)"
assert "scenario 3: both children verified suspended" \
  "$([[ "$last_output" == *"(child) child-a verified suspended"* && "$last_output" == *"(child) child-b verified suspended"* ]]; echo $?)"
root_line=$(grep -n "root-app verified suspended" <<<"$last_output" | head -1 | cut -d: -f1)
child_a_line=$(grep -n "child-a verified suspended" <<<"$last_output" | head -1 | cut -d: -f1)
assert "scenario 3: root suspended strictly before any child (ordering)" \
  "$([[ -n "$root_line" && -n "$child_a_line" && "$root_line" -lt "$child_a_line" ]]; echo $?)"
first_set_target=$(head -1 "$state3/call-order.log" | awk '{print $3}')
assert "scenario 3: the FIRST 'app set --sync-policy none' call was for root-app (disable-before-wait applies per app, root processed first)" \
  "$([[ "$first_set_target" == "root-app" ]]; echo $?)"
disable_line=$(grep -n "disabling sync policy on root-app" <<<"$last_output" | head -1 | cut -d: -f1)
quiescence_line=$(grep -n "checking root-app for any active or queued operation" <<<"$last_output" | head -1 | cut -d: -f1)
assert "scenario 3: root's automation is disabled BEFORE its operation-quiescence check runs (closes the new-operation race)" \
  "$([[ -n "$disable_line" && -n "$quiescence_line" && "$disable_line" -lt "$quiescence_line" ]]; echo $?)"

### Scenario 4 (Codex's exact counterexample): phase Succeeded, argocd calls all ###
### succeed and genuinely return automated: {} (still present), but jq exits ###
### non-zero specifically when queried about syncPolicy.automated. Must REFUSE, ###
### never report success. ###
bindir4=$(mock_bin_dir scenario4)
cat >"$bindir4/argocd" <<'EOF'
#!/usr/bin/env bash
app="$3"
if [[ "$1" == "app" && "$2" == "get" ]]; then
  echo '{"kind":"Application","metadata":{"name":"'"$app"'"},"status":{"operationState":{"phase":"Succeeded"}},"spec":{"syncPolicy":{"automated":{}}},"operation":null}'
  exit 0
fi
if [[ "$1" == "app" && "$2" == "set" ]]; then
  exit 0
fi
echo "mock argocd: unexpected args: $*" >&2
exit 1
EOF
# Resolve the actual jq binary, not the mise shim: invoking the shim from a
# deliberately altered PATH (as this test does) can hang on mise's
# untrusted-directory handling rather than exec jq — the same environmental issue
# Codex's review independently hit and worked around (docs/PROGRESS.md session log
# 2026-09-09T13:29:08-06:00). This is a test-harness workaround, not a change to
# the script under test.
real_jq=$(command -v jq)
if [[ "$real_jq" == *"/mise/shims/"* ]]; then
  real_jq=$(find "$HOME/.local/share/mise/installs/jq" -maxdepth 2 -type f -name jq 2>/dev/null | sort -V | tail -1)
fi
if [[ -z "$real_jq" || ! -x "$real_jq" ]]; then
  echo "FAIL: could not resolve a non-shim jq binary for the test mock; aborting" >&2
  exit 1
fi
cat >"$bindir4/jq" <<EOF
#!/usr/bin/env bash
# Real jq for shape/phase/.operation checks (needed so quiescence passes and the
# script reaches final verification), but ALWAYS fails specifically for the
# syncPolicy.automated filter — simulating a targeted parser failure on the exact
# field whose value genuinely indicates "still automated, not suspended."
for a in "\$@"; do
  if [[ "\$a" == *"syncPolicy.automated"* ]]; then
    echo "mock jq: simulated targeted parser failure on syncPolicy.automated" >&2
    exit 4
  fi
done
exec "$real_jq" "\$@"
EOF
chmod +x "$bindir4/argocd" "$bindir4/jq"

run_with_mocks "$bindir4" "${common_args[@]}"
assert "scenario 4 (Codex counterexample — targeted jq failure on a genuinely-still-automated app): script exits non-zero" \
  "$([[ "$last_exit" -ne 0 ]]; echo $?)"
assert "scenario 4: script never claims verified suspended" \
  "$([[ "$last_output" != *"verified suspended"* ]]; echo $?)"
assert "scenario 4: error output attributes the failure to syncPolicy.automated, not a false positive" \
  "$([[ "$last_output" == *"could not determine syncPolicy.automated"* ]]; echo $?)"

### Scenario 5: malformed / wrong-Application-shaped response (metadata.name ###
### mismatch) must be refused, never trusted. ###
bindir5=$(mock_bin_dir scenario5)
cat >"$bindir5/argocd" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "app" && "$2" == "get" ]]; then
  echo '{"kind":"Application","metadata":{"name":"some-other-app"},"status":{"operationState":{"phase":"None"}},"spec":{"syncPolicy":{}},"operation":null}'
  exit 0
fi
if [[ "$1" == "app" && "$2" == "set" ]]; then
  exit 0
fi
echo "mock argocd: unexpected args: $*" >&2
exit 1
EOF
chmod +x "$bindir5/argocd"

run_with_mocks "$bindir5" "${common_args[@]}"
assert "scenario 5 (metadata.name mismatch): script exits non-zero" "$([[ "$last_exit" -ne 0 ]]; echo $?)"
assert "scenario 5: error names the shape/identity mismatch" \
  "$([[ "$last_output" == *"not valid Application-shaped JSON"* ]]; echo $?)"

### Scenario 6: operationState.phase is terminal but .operation (a queued, ###
### not-yet-started request) is set — must still be treated as active, proving ###
### .operation is actually examined, not just operationState.phase. ###
bindir6=$(mock_bin_dir scenario6)
state6="$work/scenario6-state"
mkdir -p "$state6"
cat >"$bindir6/argocd" <<EOF
#!/usr/bin/env bash
app="\$3"
if [[ "\$1" == "app" && "\$2" == "get" ]]; then
  if [[ -f "$state6/terminated" ]]; then
    echo '{"kind":"Application","metadata":{"name":"'"\$app"'"},"status":{"operationState":{"phase":"None"}},"spec":{"syncPolicy":{}},"operation":null}'
  else
    echo '{"kind":"Application","metadata":{"name":"'"\$app"'"},"status":{"operationState":{"phase":"None"}},"spec":{"syncPolicy":{}},"operation":{"sync":{}}}'
  fi
  exit 0
fi
if [[ "\$1" == "app" && "\$2" == "set" ]]; then
  exit 0
fi
if [[ "\$1" == "app" && "\$2" == "terminate-op" ]]; then
  touch "$state6/terminated"
  exit 0
fi
echo "mock argocd: unexpected args: \$*" >&2
exit 1
EOF
chmod +x "$bindir6/argocd"

run_with_mocks "$bindir6" "${common_args[@]}"
assert "scenario 6 (.operation queued despite terminal operationState.phase): script exits 0 after terminating the queued operation" \
  "$([[ "$last_exit" -eq 0 ]]; echo $?)"
assert "scenario 6: script actually called terminate-op (proving .operation was examined, not ignored)" \
  "$([[ -f "$state6/terminated" ]]; echo $?)"

### Scenario 7 (Codex's third-review exact counterexample): argocd succeeds and ###
### returns valid JSON, but the response is INCOMPLETE — only {"metadata":{"name": ###
### ...}}, no .spec/.status at all. The prior shape check only required kind/name ###
### to match, so this was wrongly accepted and every downstream field lookup then ###
### legitimately (but meaninglessly) reported "absent" — an incomplete response ###
### must now be refused as untrustworthy, distinct from a genuinely-quiesced app. ###
bindir7=$(mock_bin_dir scenario7)
cat >"$bindir7/argocd" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "app" && "$2" == "get" ]]; then
  echo '{"metadata":{"name":"'"$3"'"}}'
  exit 0
fi
if [[ "$1" == "app" && "$2" == "set" ]]; then
  exit 0
fi
echo "mock argocd: unexpected args: $*" >&2
exit 1
EOF
chmod +x "$bindir7/argocd"

run_with_mocks "$bindir7" "${common_args[@]}"
assert "scenario 7 (incomplete Application response, no .spec): script exits non-zero" \
  "$([[ "$last_exit" -ne 0 ]]; echo $?)"
assert "scenario 7: script never claims verified suspended" \
  "$([[ "$last_output" != *"verified suspended"* ]]; echo $?)"
assert "scenario 7: error names the shape/identity mismatch (same class as scenario 5, not a silent 'field absent')" \
  "$([[ "$last_output" == *"not valid Application-shaped JSON"* ]]; echo $?)"

echo
if [[ "$fail_count" -eq 0 ]]; then
  echo "ALL PASS (0 failures)"
  exit 0
else
  echo "$fail_count assertion(s) FAILED"
  exit 1
fi
