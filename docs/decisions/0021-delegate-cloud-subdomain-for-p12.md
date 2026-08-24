# ADR 0021: Delegate cloud.bedoux.com for P12

- Status: Superseded by 0022
- Date: 2026-08-23

Supersedes ADR 0020.

## Context

ADR 0020 initially targeted the `bedoux.com` apex and `www.bedoux.com`. The pre-apply DNS
review then established that both names are already serving the owner's Shopify domain through
the existing non-Route 53 DNS provider. Replacing the parent nameserver set would unnecessarily
disrupt that independent storefront.

The owner confirmed `cloud.bedoux.com` as the dedicated Bedoux Commerce Cloud hostname. A
read-only DNS check found no existing delegation or address record for that child name.

## Decision

- Shopify retains `bedoux.com` and `www.bedoux.com`, their current records, and the parent
  domain's existing authoritative nameservers.
- P12 uses exactly `cloud.bedoux.com`. Terraform creates a Route 53 public hosted zone for that
  child domain and a regional, non-exportable ACM certificate covering `cloud.bedoux.com` only.
- The owner delegates only the `cloud` child zone by adding its four Route 53 nameservers as an
  `NS` record in the existing parent DNS service. The parent nameserver set is never replaced.
- Terraform does not manage the parent zone, Shopify records, domain registration, transfer, or
  renewal.
- Hosted-zone persistence still requires explicit owner approval during the live-session plan
  review. P12.3 records and verifies the resulting persistent or teardown state.

## Consequences

- The AWS learning endpoint is isolated from the Shopify storefront; P12 work cannot overwrite
  the apex or `www` records through Terraform.
- The live browser checklist adds one child-zone delegation at the existing DNS provider instead
  of changing registrar nameservers for the whole domain.
- ACM validation occurs entirely inside the delegated Route 53 child zone after public NS
  delegation is verified.
- Rollback removes the parent `cloud.bedoux.com` NS delegation before deleting its Route 53
  hosted zone, avoiding a dangling delegation.
