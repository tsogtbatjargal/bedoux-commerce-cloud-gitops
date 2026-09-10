#!/usr/bin/env bash
# Local, no-cluster regression test for scripts/gitops-mvp-up.sh's ownership
# check ordering, using mock kind/kubectl/podman/helm on an isolated PATH.
# Reproduces and closes the exact defect from Codex's GO-MVP follow-up review
# (docs/PROGRESS.md session log 2026-09-09T20:55:51-06:00, DEF-014): the prior
# version reused an existing, unmarked cluster and had ALREADY overwritten the
# node's git snapshot, built/loaded images, and installed/patched Argo CD before
# ever checking the ownership marker — and even then only refused if an
# argocd/bedoux-demo Application already existed, otherwise it silently ADOPTED
# the cluster. This test proves the ownership check now happens BEFORE any of
# that: a mock `podman`/`helm` that fails loudly if invoked at all proves
# gitops-mvp-up.sh never reaches image-build/cluster-mutation for an unmarked
# reused cluster — it refuses first.
#
# Real `git` is used (the snapshot-build step is pure local git, no cluster
# contact, genuinely harmless to run for real against this checkout).

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
  echo "bedoux-gitops-mvp"
  exit 0
fi
echo "MUTATION NOT ALLOWED: kind was invoked to modify the cluster: $*" >&2
exit 1
EOF

cat >"$bindir/kubectl" <<'EOF'
#!/usr/bin/env bash
args="$*"
case "$args" in
  *"kube-system get configmap bedoux-gitops-mvp-owner"*)
    # No marker -> this cluster was not created by gitops-mvp-up.sh.
    exit 1
    ;;
  *"wait --for=condition=Ready node"*)
    echo "MUTATION NOT ALLOWED: node-ready wait ran before the ownership check refused: $args" >&2
    exit 1
    ;;
  *)
    echo "MUTATION NOT ALLOWED: kubectl was invoked against the cluster: $args" >&2
    exit 1
    ;;
esac
EOF

cat >"$bindir/podman" <<'EOF'
#!/usr/bin/env bash
echo "MUTATION NOT ALLOWED: podman was invoked (image build/load) before the ownership check refused: $*" >&2
exit 1
EOF

cat >"$bindir/helm" <<'EOF'
#!/usr/bin/env bash
echo "MUTATION NOT ALLOWED: helm was invoked before the ownership check refused: $*" >&2
exit 1
EOF

chmod +x "$bindir/kind" "$bindir/kubectl" "$bindir/podman" "$bindir/helm"

set +e
last_output=$(PATH="$bindir:$PATH" "$script" 2>&1)
last_exit=$?
set -e

assert "REPRO CLOSED: unmarked reused cluster -> gitops-mvp-up.sh refuses (exit non-zero)" \
  "$([[ "$last_exit" -ne 0 ]]; echo $?)"
assert "unmarked reused cluster: error explains it does not look like a cluster this script created" \
  "$([[ "$last_output" == *"does not look like a cluster gitops-mvp-up.sh created"* ]]; echo $?)"
assert "REPRO CLOSED: no image build/load was attempted (podman never invoked against the cluster)" \
  "$([[ "$last_output" != *"MUTATION NOT ALLOWED: podman"* ]]; echo $?)"
assert "REPRO CLOSED: no Argo CD install/patch was attempted (helm/kubectl never invoked to mutate the cluster)" \
  "$([[ "$last_output" != *"MUTATION NOT ALLOWED: kubectl"* && "$last_output" != *"MUTATION NOT ALLOWED: helm"* ]]; echo $?)"
assert "no node-readiness wait or any other kind mutation call happened after the refusal" \
  "$([[ "$last_output" != *"MUTATION NOT ALLOWED: kind"* ]]; echo $?)"

echo
if [[ "$fail_count" -eq 0 ]]; then
  echo "ALL PASS (0 failures)"
  exit 0
else
  echo "$fail_count assertion(s) FAILED"
  exit 1
fi
