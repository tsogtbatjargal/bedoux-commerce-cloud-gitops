#!/usr/bin/env bash
# Local, no-cluster regression test for scripts/gitops-mvp-up.sh's kind-inventory
# error handling (DEF-015): a failed `kind get clusters` query must be refused
# outright, never silently treated as "cluster absent" and fallen through to
# cluster creation. Uses mock kind/kubectl/podman/helm on an isolated PATH, the
# same pattern as test-gitops-mvp-up-ownership.sh. A mock `kind` whose "create
# cluster" subcommand fails loudly, plus mock kubectl/podman/helm that fail
# loudly if invoked at all, proves gitops-mvp-up.sh never reaches cluster
# creation or any other mutation once the inventory query itself fails.

set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gitops-mvp-up.sh"
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

bindir="$work/mock"
mkdir -p "$bindir"

cat >"$bindir/kind" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "get" && "$2" == "clusters" ]]; then
  echo "Kind-cluster-inventory-error: some kind clusters unavailable, corrupted state found." >&2
  exit 1
fi
echo "MUTATION NOT ALLOWED: kind was invoked to modify the cluster: $*" >&2
exit 1
EOF

cat >"$bindir/kubectl" <<'EOF'
#!/usr/bin/env bash
echo "MUTATION NOT ALLOWED: kubectl was invoked against the cluster: $*" >&2
exit 1
EOF

cat >"$bindir/podman" <<'EOF'
#!/usr/bin/env bash
echo "MUTATION NOT ALLOWED: podman was invoked (image build/load) before the inventory-error refusal: $*" >&2
exit 1
EOF

cat >"$bindir/helm" <<'EOF'
#!/usr/bin/env bash
echo "MUTATION NOT ALLOWED: helm was invoked before the inventory-error refusal: $*" >&2
exit 1
EOF

chmod +x "$bindir/kind" "$bindir/kubectl" "$bindir/podman" "$bindir/helm"

set +e
last_output=$(PATH="$bindir:$PATH" "$script" 2>&1)
last_exit=$?
set -e

assert "REPRO CLOSED: failed 'kind get clusters' inventory query -> gitops-mvp-up.sh refuses (exit non-zero)" \
  "$([[ "$last_exit" -ne 0 ]]; echo $?)"
assert "inventory-error output explains the query itself failed, not a confirmed-empty result" \
  "$([[ "$last_output" == *"'kind get clusters' failed"* ]]; echo $?)"
assert "REPRO CLOSED: no 'kind create cluster' or other kind mutation was attempted" \
  "$([[ "$last_output" != *"MUTATION NOT ALLOWED: kind"* ]]; echo $?)"
assert "REPRO CLOSED: no kubectl mutation was attempted (no node-ready wait, no ownership marker write)" \
  "$([[ "$last_output" != *"MUTATION NOT ALLOWED: kubectl"* ]]; echo $?)"
assert "REPRO CLOSED: no image build/load was attempted (podman never invoked)" \
  "$([[ "$last_output" != *"MUTATION NOT ALLOWED: podman"* ]]; echo $?)"
assert "REPRO CLOSED: no Argo CD install/patch was attempted (helm never invoked)" \
  "$([[ "$last_output" != *"MUTATION NOT ALLOWED: helm"* ]]; echo $?)"

echo
if [[ "$fail_count" -eq 0 ]]; then
  echo "ALL PASS (0 failures)"
  exit 0
else
  echo "$fail_count assertion(s) FAILED"
  exit 1
fi
