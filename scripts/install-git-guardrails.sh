#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/install-git-guardrails.sh <--dry-run|--install>

Installs the Bedoux local pre-push guardrail into this clone's Git hooks directory.

  --dry-run  Print the target and make no changes.
  --install  Install the hook. Refuses to overwrite an existing pre-push hook.

The hook blocks direct pushes of local main. It is a compensating local control,
not GitHub server-side branch protection.
EOF
}

if (( $# != 1 )); then
  usage >&2
  exit 2
fi

mode="$1"
if [[ "$mode" != "--dry-run" && "$mode" != "--install" ]]; then
  usage >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_hook="$repo_root/scripts/git-hooks/pre-push"
target_hook="$(git -C "$repo_root" rev-parse --git-path hooks/pre-push)"

if [[ "$mode" == "--dry-run" ]]; then
  printf 'DRY RUN: install %s -> %s\n' "$source_hook" "$target_hook"
  exit 0
fi

if [[ -e "$target_hook" ]]; then
  printf 'refusing to overwrite existing hook: %s\n' "$target_hook" >&2
  exit 1
fi

install -D -m 0755 "$source_hook" "$target_hook"
printf 'installed Bedoux pre-push guardrail: %s\n' "$target_hook"
