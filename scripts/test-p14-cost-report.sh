#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
report="$repo_root/docs/p10-p13-cost-report.md"
fixture_dir=""

cleanup() {
  if [[ -n "$fixture_dir" && -d "$fixture_dir" && "$fixture_dir" == /tmp/bedoux-p14-cost-test.* ]]; then
    rm -rf -- "$fixture_dir"
  fi
}
trap cleanup EXIT

validate_report() {
  local candidate="$1"
  local phase_count phase_total month_count track_total cap_violations service_count service_total

  read -r phase_count phase_total < <(
    awk -F '|' '
      function trim(value) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        return value
      }
      {
        phase = trim($2)
        if (phase ~ /^P1[0-3]$/) {
          count++
          total += trim($4)
        }
      }
      END { printf "%d %.6f\n", count, total }
    ' "$candidate"
  )

  [[ "$phase_count" -eq 4 ]] || return 1
  [[ "$phase_total" == "4.939738" ]] || return 1

  read -r month_count track_total cap_violations < <(
    awk -F '|' '
      function trim(value) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        return value
      }
      {
        period = trim($2)
        if (period ~ /^2026-(08|09)/) {
          account_usage = trim($3) + 0
          track_usage = trim($4) + 0
          cap = trim($5) + 0
          count++
          total += track_usage
          if (account_usage > cap || track_usage > account_usage) {
            violations++
          }
        }
      }
      END { printf "%d %.6f %d\n", count, total, violations }
    ' "$candidate"
  )

  [[ "$month_count" -eq 2 ]] || return 1
  [[ "$track_total" == "4.939738" ]] || return 1
  [[ "$cap_violations" -eq 0 ]] || return 1

  read -r service_count service_total < <(
    awk -F '|' '
      function trim(value) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        return value
      }
      {
        service = trim($2)
        if (service ~ /^(EKS control planes|Route 53|EC2 Spot compute|Application Load Balancers|VPC|Other)$/) {
          count++
          total += trim($3)
        }
      }
      END { printf "%d %.6f\n", count, total }
    ' "$candidate"
  )

  [[ "$service_count" -eq 6 ]] || return 1
  [[ "$service_total" == "4.939738" ]] || return 1

  grep -Fq 'September actual USD 0.502 and forecast USD' "$candidate" || return 1
  grep -Fq 'positive `Usage` record type' "$candidate" || return 1
  grep -Fq 'credit-adjusted' "$candidate" || return 1
  grep -Fq 'calendar-window attributions, not resource-level chargeback' "$candidate" || return 1
}

validate_report "$report"

# Prove the arithmetic/cap check rejects a materially divergent report fixture.
fixture_dir="$(mktemp -d /tmp/bedoux-p14-cost-test.XXXXXX)"
cp "$report" "$fixture_dir/report.md"
sed -i 's/| P13 | 2026-08-27–2026-09-01 | 2.975835 |/| P13 | 2026-08-27–2026-09-01 | 22.975835 |/' \
  "$fixture_dir/report.md"
if validate_report "$fixture_dir/report.md" >/dev/null 2>&1; then
  printf '%s\n' 'cost-report validation accepted an inflated P13 fixture' >&2
  exit 1
fi

printf '%s\n' 'P14.4 cost-report arithmetic, cap, and divergent fixture OK'
