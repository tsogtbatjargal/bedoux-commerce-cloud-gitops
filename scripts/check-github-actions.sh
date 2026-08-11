#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/check-github-actions.sh [--help]

Verify that every external action used by .github/workflows is pinned to an
immutable 40-character commit SHA. Local and docker:// actions are ignored.
EOF
}

case "${1:-}" in
  "")
    ;;
  --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

workflow_dir=".github/workflows"
if [[ ! -d "$workflow_dir" ]]; then
  printf 'missing workflow directory: %s\n' "$workflow_dir" >&2
  exit 1
fi

checked=0
failed=0
while IFS=: read -r file line content; do
  ref="${content#*uses:}"
  ref="${ref%%#*}"
  ref="${ref#"${ref%%[![:space:]]*}"}"
  ref="${ref%"${ref##*[![:space:]]}"}"

  case "$ref" in
    ./*|docker://*)
      continue
      ;;
  esac

  checked=$((checked + 1))
  if [[ ! "$ref" =~ ^[^[:space:]@]+@[0-9a-f]{40}$ ]]; then
    printf '%s:%s: external action is not pinned to a full commit SHA: %s\n' \
      "$file" "$line" "$ref" >&2
    failed=1
  fi
done < <(grep -nHE '^[[:space:]]*(-[[:space:]]*)?uses:' "$workflow_dir"/*.yml)

if (( checked == 0 )); then
  printf 'no external GitHub Actions references found\n' >&2
  exit 1
fi

if (( failed != 0 )); then
  exit 1
fi

printf 'actions-check OK (%d immutable external action references)\n' "$checked"
