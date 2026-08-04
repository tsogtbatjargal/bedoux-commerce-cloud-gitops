#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/discover-alb-arn-suffix.sh

Prints only the non-sensitive Application Load Balancer ARN suffix (app/name/id)
for the current bedoux Ingress. It performs read-only kubectl and AWS CLI calls,
does not print a full ARN, account ID, DNS name, or credentials, and writes no files.

Run only after the P8 session Ingress has a hostname and use the result only as
the temporary TF_VAR_observability_alb_arn_suffix input for the reviewed alarm plan.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if (( $# != 0 )); then
  usage >&2
  exit 2
fi

alb_dns_name="$(kubectl -n bedoux get ingress bedoux -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
test -n "$alb_dns_name"

alb_arn="$(aws elbv2 describe-load-balancers --profile bedoux-admin --region ca-central-1 \
  --query "LoadBalancers[?DNSName=='${alb_dns_name}'].LoadBalancerArn | [0]" --output text)"
test -n "$alb_arn"
test "$alb_arn" != "None"

alb_arn_suffix="${alb_arn#*:loadbalancer/}"
if [[ ! "$alb_arn_suffix" =~ ^app/[A-Za-z0-9-]+/[0-9a-f]+$ ]]; then
  printf '%s\n' 'REFUSING: discovered value is not an Application Load Balancer ARN suffix.' >&2
  exit 1
fi

printf '%s\n' "$alb_arn_suffix"
unset alb_arn alb_dns_name alb_arn_suffix
