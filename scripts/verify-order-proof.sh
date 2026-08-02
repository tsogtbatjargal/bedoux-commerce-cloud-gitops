#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: BEDOUX_BASE_URL=http://host BEDOUX_ORDER_PROOF_CONFIRM=1 scripts/verify-order-proof.sh [--dry-run]

Performs one bounded synthetic checkout proof against an already-deployed Bedoux
API route. It first requires healthy, explicitly enabled ordering; then it reads
the catalog, creates one quantity-one order for the first product, and retrieves
that order again. It never prints the base URL or order ID.

Set BEDOUX_ORDER_PROOF_CONFIRM=1 to permit the single POST. --dry-run performs
no HTTP requests and prints the intended sequence instead.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if (( $# > 1 )) || { (( $# == 1 )) && [[ "$1" != "--dry-run" ]]; }; then
  usage >&2
  exit 2
fi

dry_run=false
if (( $# == 1 )); then
  dry_run=true
fi

base_url="${BEDOUX_BASE_URL:-}"
if [[ -z "$base_url" ]]; then
  printf '%s\n' 'BEDOUX_BASE_URL is required.' >&2
  exit 2
fi
base_url="${base_url%/}"

if "$dry_run"; then
  printf '%s\n' 'DRY RUN: GET /api/health, GET /api/products, POST one quantity-one order, GET its confirmation.'
  exit 0
fi

if [[ "${BEDOUX_ORDER_PROOF_CONFIRM:-}" != "1" ]]; then
  printf '%s\n' 'Refusing: set BEDOUX_ORDER_PROOF_CONFIRM=1 before creating the single synthetic order.' >&2
  exit 2
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

curl_args=(--fail --silent --show-error --connect-timeout 5 --max-time 15)

curl "${curl_args[@]}" "$base_url/api/health" > "$work_dir/health.json"
jq -e '.status == "ok" and .orders_enabled == true' "$work_dir/health.json" >/dev/null

curl "${curl_args[@]}" "$base_url/api/products" > "$work_dir/products.json"
catalog_count="$(jq 'length' "$work_dir/products.json")"
test "$catalog_count" -gt 0
product_id="$(jq -er '.[0].id' "$work_dir/products.json")"

order_status="$(curl --silent --show-error --connect-timeout 5 --max-time 15 \
  --output "$work_dir/order.json" --write-out '%{http_code}' \
  --header 'Content-Type: application/json' --request POST \
  --data "{\"items\":[{\"product_id\":\"$product_id\",\"quantity\":1}]}" \
  "$base_url/api/orders")"
test "$order_status" = "200"
order_id="$(jq -er '.id' "$work_dir/order.json")"

curl "${curl_args[@]}" "$base_url/api/orders/$order_id" > "$work_dir/confirmation.json"
jq -e --arg order_id "$order_id" \
  '.id == $order_id and .status == "submitted" and (.items | length == 1)' \
  "$work_dir/confirmation.json" >/dev/null

unset base_url product_id order_id
printf 'Synthetic order proof passed: ordering enabled, catalog_count=%s, one order created and confirmed.\n' \
  "$catalog_count"
