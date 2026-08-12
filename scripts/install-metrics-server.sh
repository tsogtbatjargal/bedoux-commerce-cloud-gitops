#!/usr/bin/env bash
set -euo pipefail

version="v0.9.0"
manifest_sha256="1cec29a5267809306a2c6ec74a3e449abbb705b4a8beed0c8a1963910f72c79b"
context="${KUBE_CONTEXT:-kind-bedoux}"
mode=""

usage() {
  cat <<'EOF'
Usage: scripts/install-metrics-server.sh <--dry-run|--apply> [--context NAME]

Install the pinned Metrics Server release used by the local HPA proof.

  --dry-run       Print the pinned URL, checksum, and intended commands.
  --apply         Download, verify, and apply the manifest to the named cluster.
  --context NAME  Kubernetes context (default: KUBE_CONTEXT or kind-bedoux).

The kind proof adds --kubelet-insecure-tls after checksum verification because
the disposable kind node certificate is not signed by a trusted cluster CA.
EOF
}

while (($#)); do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --dry-run|--apply)
      if [[ -n "$mode" ]]; then
        usage >&2
        exit 2
      fi
      mode="${1#--}"
      ;;
    --context)
      if (($# < 2)); then
        usage >&2
        exit 2
      fi
      context="$2"
      shift
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ -z "$mode" ]]; then
  usage >&2
  exit 2
fi

manifest_url="https://github.com/kubernetes-sigs/metrics-server/releases/download/${version}/components.yaml"

if [[ "$mode" == "dry-run" ]]; then
  printf 'DRY RUN: metrics-server %s\n' "$version"
  printf 'DRY RUN: URL %s\n' "$manifest_url"
  printf 'DRY RUN: SHA256 %s\n' "$manifest_sha256"
  printf 'DRY RUN: kubectl --context %s apply -f <verified components.yaml>\n' "$context"
  printf 'DRY RUN: patch metrics-server with --kubelet-insecure-tls for kind\n'
  exit 0
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
manifest_file="$tmp_dir/components.yaml"

curl --fail --silent --show-error --location "$manifest_url" --output "$manifest_file"
actual_sha256="$(sha256sum "$manifest_file" | cut -d' ' -f1)"
if [[ "$actual_sha256" != "$manifest_sha256" ]]; then
  printf 'metrics-server manifest checksum mismatch: expected %s, got %s\n' \
    "$manifest_sha256" "$actual_sha256" >&2
  exit 1
fi

kubectl --context "$context" apply --filename "$manifest_file"
existing_args="$(kubectl --context "$context" --namespace kube-system \
  get deployment metrics-server --output jsonpath='{.spec.template.spec.containers[0].args}')"
if [[ "$existing_args" != *"--kubelet-insecure-tls"* ]]; then
  kubectl --context "$context" --namespace kube-system patch deployment metrics-server \
    --type='json' \
    --patch='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
fi
kubectl --context "$context" --namespace kube-system rollout status \
  deployment/metrics-server --timeout=180s
printf 'metrics-server %s is ready on context %s\n' "$version" "$context"
