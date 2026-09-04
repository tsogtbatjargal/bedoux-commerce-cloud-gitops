#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/p12-tls-proof.sh [--dry-run|--execute]

Proves P12.2's public HTTPS and HTTP-to-HTTPS redirect contract for exactly
bedoux.ca and www.bedoux.ca. The default is --dry-run and performs no network
requests. --execute uses curl's normal CA and hostname verification; it never
changes AWS, DNS, Kubernetes, or local files.
EOF
}

mode="${1:---dry-run}"
case "$mode" in
  --help|-h)
    usage
    exit 0
    ;;
  --dry-run)
    printf '%s\n' 'DRY RUN: verify HTTPS health and HTTP 301 redirect for bedoux.ca and www.bedoux.ca.'
    exit 0
    ;;
  --execute)
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

for domain in bedoux.ca www.bedoux.ca; do
  health_json="$(curl --fail --silent --show-error --connect-timeout 10 --max-time 30 \
    "https://${domain}/api/health")"
  python scripts/lib/gate_checks.py health-response-exact \
    --expected-json '{"status": "ok", "orders_enabled": false}' <<<"$health_json"

  headers="$(curl --silent --show-error --head --connect-timeout 10 --max-time 30 \
    "http://${domain}/" | tr -d '\r')"
  status_code="$(awk 'NR == 1 { print $2 }' <<<"$headers")"
  location="$(awk 'tolower($1) == "location:" { print $2; exit }' <<<"$headers")"

  test "$status_code" = "301"
  case "$location" in
    "https://${domain}/"|"https://${domain}:443/") ;;
    *)
      printf 'REFUSING: unexpected redirect Location for %s: %s\n' "$domain" "$location" >&2
      exit 1
      ;;
  esac

  printf 'PASS: %s has trusted HTTPS health and an HTTP 301 redirect to HTTPS.\n' "$domain"
done

unset domain health_json headers location status_code
