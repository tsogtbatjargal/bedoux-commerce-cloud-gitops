#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
walkthrough="$repo_root/docs/interview/walkthrough-script.md"
diagram="$repo_root/docs/diagrams/optimization-track.drawio"
svg="$repo_root/docs/diagrams/optimization-track.svg"
system_context="$repo_root/docs/diagrams/system-context.drawio"
request_path="$repo_root/docs/diagrams/request-path.drawio"
ci_cd="$repo_root/docs/diagrams/ci-cd.drawio"

for file in "$walkthrough" "$diagram" "$svg" "$system_context" "$request_path" "$ci_cd"; do
  if [[ ! -f "$file" ]]; then
    echo "missing P14.5 interview artifact: ${file#"$repo_root/"}" >&2
    exit 1
  fi
done

drawio_count=0
svg_count=0
for file in "$repo_root"/docs/diagrams/*.drawio; do
  [[ -e "$file" ]] && ((drawio_count += 1))
done
for file in "$repo_root"/docs/diagrams/*.svg; do
  [[ -e "$file" ]] && ((svg_count += 1))
done
if (( drawio_count < 7 || svg_count != drawio_count )); then
  echo "expected at least seven matching drawio/svg artifacts; found $drawio_count/$svg_count" >&2
  exit 1
fi

for phase in P10 P11 P12 P13 P14; do
  grep -Fq "$phase" "$walkthrough" || {
    echo "walkthrough does not mention $phase" >&2
    exit 1
  }
  grep -Fq "$phase" "$diagram" || {
    echo "optimization diagram does not mention $phase" >&2
    exit 1
  }
done

for evidence in 'bedoux.ca' '33,507/33,507' '90/10' 'USD 4.939738' '229m'; do
  grep -Fq "$evidence" "$walkthrough" || {
    echo "walkthrough is missing evidence: $evidence" >&2
    exit 1
  }
done

for evidence in 'bedoux.ca' '33,507 / 33,507' '90/10' 'USD 4.939738' '229m'; do
  grep -Fq "$evidence" "$diagram" || {
    echo "diagram source is missing evidence: $evidence" >&2
    exit 1
  }
  grep -Fq "$evidence" "$svg" || {
    echo "diagram export is missing evidence: $evidence" >&2
    exit 1
  }
done

grep -Fq 'bedoux.ca / www aliases only during sessions' "$system_context"
grep -Fq 'frontend proxies /api internally' "$system_context"
grep -Fq 'P13 stage: web/web-canary = 90/10' "$request_path"
grep -Fq 'SPDX + ephemeral-key sign/verify' "$ci_cd"
grep -Fq 'reconcile 100/0 before cleanup' "$ci_cd"

for stale in 'production profile only' '/api → API'; do
  if grep -Fq "$stale" "$system_context"; then
    echo "system-context retained stale claim: $stale" >&2
    exit 1
  fi
done
for stale in 'HTTP only' 'no Route53 / ACM'; do
  if grep -Fq "$stale" "$request_path"; then
    echo "request-path retained stale claim: $stale" >&2
    exit 1
  fi
done

spoken_words="$({ sed -n 's/^> *//p' "$walkthrough" || true; } | wc -w)"
if (( spoken_words > 1400 )); then
  echo "walkthrough has $spoken_words spoken words; maximum is 1400" >&2
  exit 1
fi

format_duration() {
  local seconds="$1"
  printf '%d:%02d' "$((seconds / 60))" "$((seconds % 60))"
}

slow_seconds="$(((spoken_words * 60 + 50) / 100 + 60))"
typical_seconds="$(((spoken_words * 60 + 65) / 130 + 60))"
timing_row="| P14.5 extension (2026-09-02) | $spoken_words | $(format_duration "$slow_seconds") | $(format_duration "$typical_seconds") | Pass |"
grep -Fqx "$timing_row" "$walkthrough" || {
  echo "walkthrough timing row does not match its $spoken_words spoken words" >&2
  exit 1
}

echo "P14.5 interview evidence and ${spoken_words}-word timing bound OK"
