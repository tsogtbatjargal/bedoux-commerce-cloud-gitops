#!/usr/bin/env bash

set -uo pipefail

required_tools=(
  git
  make
  xmllint
  python3
  node
  npm
  podman
  aws
  kubectl
  eksctl
  kind
  helm
  terraform
)

missing=0

for tool in "${required_tools[@]}"; do
  if command -v "${tool}" >/dev/null 2>&1; then
    tool_path="$(command -v "${tool}")"
    printf '%-12s available  %s\n' "${tool}" "${tool_path}"
  else
    printf '%-12s missing\n' "${tool}"
    missing=1
  fi
done

if (( missing != 0 )); then
  printf '\nOne or more project prerequisites are missing.\n'
  exit 1
fi

printf '\nAll project prerequisites are available.\n'

