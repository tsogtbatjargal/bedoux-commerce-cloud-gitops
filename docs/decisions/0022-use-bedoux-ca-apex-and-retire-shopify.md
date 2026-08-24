# ADR 0022: Use the bedoux.ca apex for P12 and retire Shopify

- Status: Accepted
- Date: 2026-08-24

Supersedes ADR 0021.

## Context

ADR 0021 preserved the Shopify-connected `bedoux.com` apex by assigning P12 the delegated
`cloud.bedoux.com` child domain. The owner then corrected the intended project domain to
`bedoux.ca` and decided to retire Shopify because its recurring cost is no longer justified.

A read-only DNS check found that `bedoux.ca` is not currently unused: its authoritative DNS is
outside Route 53, the apex resolves to Shopify, and `www.bedoux.ca` aliases Shopify. No MX or
apex TXT answer was found. Those existing website records are now an intentional cutover target,
not records that P12 must preserve.

## Decision

- P12 uses a Route 53 public hosted zone for the apex `bedoux.ca` domain.
- The regional, non-exportable ACM certificate covers `bedoux.ca` and the single website alias
  `www.bedoux.ca`.
- During the reviewed live P12.1 session, the owner replaces the registrar's current
  authoritative nameservers with the four nameservers assigned to the new Route 53 zone.
- The existing Shopify apex and `www` records are not copied into Route 53. Shopify is retired
  deliberately; Terraform does not manage or cancel the Shopify account.
- Terraform manages the hosted zone, certificate, DNS validation records, and certificate
  validation. It does not manage domain registration, transfer, renewal, or registrar settings.
- P12.2 will add the Route 53 aliases that direct `bedoux.ca` and `www.bedoux.ca` to the ALB and
  will prove HTTPS plus HTTP-to-HTTPS redirect behavior.
- Hosted-zone persistence still requires explicit owner approval during the live-session plan
  review. P12.3 records and verifies the resulting persistent or teardown state.

## Consequences

- Changing the registrar delegation ends the Shopify-backed website path after DNS caches expire.
- P12.1 intentionally leaves a temporary no-site window: the new zone initially contains only
  ACM validation records, and the in-house website becomes reachable in P12.2 after the ALB and
  apex/`www` aliases exist.
- The live preflight must recheck website, MX, and TXT records and stop on any unexplained change;
  the 2026-08-24 read-only result is evidence, not permission to discard future records silently.
- Rollback restores the registrar's previous nameservers and verifies public delegation before
  deleting the Route 53 zone. The zone must never be deleted while the registrar still delegates
  `bedoux.ca` to it.
