#!/usr/bin/env bash
# Local, no-cluster regression tests for scripts/gitops-mvp-down.sh, using mock
# kind/kubectl/podman on an isolated PATH. Reproduces the exact defects from
# Codex's GO-MVP review (docs/PROGRESS.md session log 2026-09-09T20:27:22-06:00,
# DEF-014): an already-clean run (no clusters, no images) exited 1 instead of 0;
# a failed inventory query was indistinguishable from a confirmed-empty one; a
# reused/foreign cluster with no ownership marker was deleted without any check.

set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gitops-mvp-down.sh"
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
  local d="$work/$1"
  mkdir -p "$d"
  printf '%s' "$d"
}

run_with_mock() {
  local bindir="$1"
  shift
  set +e
  last_output=$(PATH="$bindir:$PATH" "$script" "$@" 2>&1)
  last_exit=$?
  set -e
}

### Scenario 1 (Codex's exact repro): no clusters, no images -> already-clean ###
### success, exit 0, not the previous pipefail-induced exit 1. ###
bindir1=$(mock_bin_dir scenario1)
cat >"$bindir1/kind" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "get" && "$2" == "clusters" ]]; then
  echo "No kind clusters found"
  exit 0
fi
exit 1
EOF
cat >"$bindir1/podman" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "images" ]]; then exit 0; fi
exit 1
EOF
chmod +x "$bindir1/kind" "$bindir1/podman"
run_with_mock "$bindir1"
assert "REPRO CLOSED: already-clean run (no clusters, no images) exits 0 (was exit 1)" "$([[ "$last_exit" -eq 0 ]]; echo $?)"
assert "already-clean run: reports cleanup complete" "$([[ "$last_output" == *"cleanup complete"* ]]; echo $?)"

### Scenario 2 (Codex's exact repro): inventory query itself fails -> refuse, ###
### never treat a failed query as proof of emptiness. ###
bindir2=$(mock_bin_dir scenario2)
cat >"$bindir2/kind" <<'EOF'
#!/usr/bin/env bash
echo "Error: could not list clusters: connection refused" >&2
exit 1
EOF
chmod +x "$bindir2/kind"
run_with_mock "$bindir2"
assert "REPRO CLOSED: inventory query failure refuses (exit non-zero), not silently treated as 'no clusters'" "$([[ "$last_exit" -ne 0 ]]; echo $?)"
assert "inventory failure: error explains it is not confirmed-empty" "$([[ "$last_output" == *"not a confirmed-empty result"* ]]; echo $?)"

### Scenario 3 (Codex's exact repro): a cluster with the target name exists but ###
### has no ownership marker -> refuse, never delete a foreign/reused cluster. ###
bindir3=$(mock_bin_dir scenario3)
cat >"$bindir3/kind" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "get" && "$2" == "clusters" ]]; then
  echo "bedoux-gitops-mvp"
  exit 0
fi
echo "mock kind: unexpected args: $*" >&2
exit 1
EOF
cat >"$bindir3/kubectl" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"kube-system get configmap bedoux-gitops-mvp-owner"* ]]; then
  exit 1
fi
echo "mock kubectl: unexpected args: $*" >&2
exit 1
EOF
chmod +x "$bindir3/kind" "$bindir3/kubectl"
run_with_mock "$bindir3"
assert "REPRO CLOSED: cluster exists without ownership marker -> refuses (never deletes a foreign cluster)" "$([[ "$last_exit" -ne 0 ]]; echo $?)"
assert "no ownership marker: error explains it does not look like a cluster this script created" "$([[ "$last_output" == *"does not look like a cluster gitops-mvp-up.sh created"* ]]; echo $?)"

### Scenario 4: a cluster WITH the ownership marker -> --dry-run proceeds to the ###
### preview (no destructive calls: no delete verb allowed in the mock). ###
bindir4=$(mock_bin_dir scenario4)
cat >"$bindir4/kind" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "get" && "$2" == "clusters" ]]; then
  echo "bedoux-gitops-mvp"
  exit 0
fi
echo "mock kind: DESTRUCTIVE CALL NOT ALLOWED IN --dry-run: $*" >&2
exit 1
EOF
cat >"$bindir4/kubectl" <<'EOF'
#!/usr/bin/env bash
args="$*"
case "$args" in
  *"kube-system get configmap bedoux-gitops-mvp-owner"*) exit 0 ;;
  *"argocd get application bedoux-demo"*"jsonpath="*) echo "mvp-deadbeef0000" ;;
  *"argocd get application bedoux-demo"*) exit 0 ;;
  *"delete"*) echo "mock kubectl: DESTRUCTIVE CALL NOT ALLOWED IN --dry-run: $args" >&2; exit 1 ;;
  *) echo "mock kubectl: unexpected args: $args" >&2; exit 1 ;;
esac
EOF
chmod +x "$bindir4/kind" "$bindir4/kubectl"
run_with_mock "$bindir4" --dry-run
assert "owned cluster, --dry-run: exits 0 without issuing any destructive call" "$([[ "$last_exit" -eq 0 ]]; echo $?)"
assert "--dry-run: reports what it would delete, including the exact image tag read from the Application" "$([[ "$last_output" == *"mvp-deadbeef0000"* ]]; echo $?)"
assert "--dry-run: never actually called a destructive verb (mock would have failed loudly)" "$([[ "$last_output" != *"NOT ALLOWED IN --dry-run"* ]]; echo $?)"

### Codex's GO-MVP follow-up review (docs/PROGRESS.md session log ###
### 2026-09-09T20:55:51-06:00, DEF-014): the prior 'mvp-*' fallback deleted a ###
### genuinely UNRELATED image whenever the exact tag could not be read, and a ###
### 'podman images' failure was swallowed by '|| true' and reported as success. ###
### Scenario 5: exact tag unreadable (Application already gone) -> podman is ###
### never even asked to list/remove anything; a mock that fails loudly on ANY ###
### podman invocation proves no fallback sweep happens at all. ###
bindir5=$(mock_bin_dir scenario5)
cat >"$bindir5/kind" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "get" && "$2" == "clusters" ]]; then
  echo "bedoux-gitops-mvp"
  exit 0
fi
if [[ "$1" == "delete" ]]; then exit 0; fi
echo "mock kind: unexpected args: $*" >&2
exit 1
EOF
cat >"$bindir5/kubectl" <<'EOF'
#!/usr/bin/env bash
args="$*"
case "$args" in
  *"kube-system get configmap bedoux-gitops-mvp-owner"*) exit 0 ;;
  *"argocd get application bedoux-demo"*) exit 1 ;;  # Application already gone
  *"delete application"*) exit 0 ;;
  *"delete namespace"*) exit 0 ;;
  *) echo "mock kubectl: unexpected args: $args" >&2; exit 1 ;;
esac
EOF
cat >"$bindir5/podman" <<'EOF'
#!/usr/bin/env bash
echo "FALLBACK SWEEP NOT ALLOWED: podman was invoked at all: $*" >&2
exit 1
EOF
chmod +x "$bindir5/kind" "$bindir5/kubectl" "$bindir5/podman"
run_with_mock "$bindir5"
assert "REPRO CLOSED: exact tag unreadable -> podman is never invoked at all (no broad fallback sweep)" \
  "$([[ "$last_output" != *"FALLBACK SWEEP NOT ALLOWED"* ]]; echo $?)"
assert "exact tag unreadable: reports image cleanup was SKIPPED, not attempted" \
  "$([[ "$last_output" == *"SKIPPING image cleanup"* ]]; echo $?)"
assert "exact tag unreadable: overall run still succeeds (skipping image cleanup is not itself a failure)" \
  "$([[ "$last_exit" -eq 0 ]]; echo $?)"

### Scenario 6: exact tag IS known, but the actual image removal genuinely fails ###
### -> the script must exit non-zero, not silently report "cleanup complete". ###
bindir6=$(mock_bin_dir scenario6)
cat >"$bindir6/kind" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "get" && "$2" == "clusters" ]]; then echo "bedoux-gitops-mvp"; exit 0; fi
if [[ "$1" == "delete" ]]; then exit 0; fi
exit 1
EOF
cat >"$bindir6/kubectl" <<'EOF'
#!/usr/bin/env bash
args="$*"
case "$args" in
  *"kube-system get configmap bedoux-gitops-mvp-owner"*) exit 0 ;;
  *"argocd get application bedoux-demo"*"jsonpath="*) echo "mvp-deadbeef0000" ;;
  *"argocd get application bedoux-demo"*) exit 0 ;;
  *"delete application"*) exit 0 ;;
  *"delete namespace"*) exit 0 ;;
  *) echo "mock kubectl: unexpected args: $args" >&2; exit 1 ;;
esac
EOF
cat >"$bindir6/podman" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "image" && "$2" == "exists" ]]; then exit 0; fi
if [[ "$1" == "rmi" ]]; then echo "mock podman: rmi genuinely failed (image in use)" >&2; exit 1; fi
echo "mock podman: unexpected args: $*" >&2
exit 1
EOF
chmod +x "$bindir6/kind" "$bindir6/kubectl" "$bindir6/podman"
run_with_mock "$bindir6"
assert "REPRO CLOSED: image removal genuinely fails -> script exits non-zero, not a silent success" \
  "$([[ "$last_exit" -ne 0 ]]; echo $?)"
assert "image removal failure: error names it a FAILURE, not a soft warning" \
  "$([[ "$last_output" == *"FAILURE: could not remove"* ]]; echo $?)"

### Scenario 7: Application delete itself genuinely fails (times out) -> the ###
### script must still attempt namespace/cluster deletion (not abort early via ###
### set -e) AND must still exit non-zero overall for the Application failure. ###
bindir7=$(mock_bin_dir scenario7)
cat >"$bindir7/kind" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "get" && "$2" == "clusters" ]]; then echo "bedoux-gitops-mvp"; exit 0; fi
if [[ "$1" == "delete" ]]; then echo "MOCK: kind delete cluster was called"; exit 0; fi
exit 1
EOF
cat >"$bindir7/kubectl" <<'EOF'
#!/usr/bin/env bash
args="$*"
case "$args" in
  *"kube-system get configmap bedoux-gitops-mvp-owner"*) exit 0 ;;
  *"argocd get application bedoux-demo"*"jsonpath="*) echo "mvp-deadbeef0000" ;;
  *"argocd get application bedoux-demo"*) exit 0 ;;
  *"delete application"*) echo "mock kubectl: Application delete timed out" >&2; exit 1 ;;
  *"delete namespace"*) echo "MOCK: namespace delete was called despite the Application delete failing"; exit 0 ;;
  *) echo "mock kubectl: unexpected args: $args" >&2; exit 1 ;;
esac
EOF
cat >"$bindir7/podman" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "image" && "$2" == "exists" ]]; then exit 0; fi
if [[ "$1" == "rmi" ]]; then exit 0; fi
exit 1
EOF
chmod +x "$bindir7/kind" "$bindir7/kubectl" "$bindir7/podman"
run_with_mock "$bindir7"
assert "Application delete fails: script still attempts namespace delete as a backstop (not aborted early)" \
  "$([[ "$last_output" == *"namespace delete was called despite the Application delete failing"* ]]; echo $?)"
assert "Application delete fails: script still attempts cluster delete too (not aborted early)" \
  "$([[ "$last_output" == *"kind delete cluster was called"* ]]; echo $?)"
assert "REPRO CLOSED: Application delete failure still makes the overall run exit non-zero" \
  "$([[ "$last_exit" -ne 0 ]]; echo $?)"

echo
if [[ "$fail_count" -eq 0 ]]; then
  echo "ALL PASS (0 failures)"
  exit 0
else
  echo "$fail_count assertion(s) FAILED"
  exit 1
fi
