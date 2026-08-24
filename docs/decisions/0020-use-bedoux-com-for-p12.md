# ADR 0020: Use bedoux.com as the P12 apex domain

- Status: Accepted
- Date: 2026-08-23

## Context

ADR 0014 requires the owner to choose a domain path before P12.1 starts: buy a new domain,
use a subdomain already controlled, or keep P12 documented-only. The owner selected the new
apex domain `bedoux.com` and confirmed that website implementation has not started.

A read-only registry check returned a record for `bedoux.com`, which means the domain is already
registered. That check does not establish who owns it or who can change its nameservers.

## Decision

- P12 will target the apex domain `bedoux.com`, with `www.bedoux.com` reserved as the initial
  website hostname alias. This records the owner-selected new-domain path required by ADR 0014.
- P12.1 may implement and validate the opt-in `route53-acm` Terraform module locally.
- Terraform will manage a Route 53 public hosted zone, an ACM certificate, DNS validation
  records, and certificate validation. It will not register, purchase, transfer, or renew the
  domain.
- No live Route 53 or ACM mutation may begin until the owner separately confirms control of
  `bedoux.com` and the ability to change its registrar nameservers.
- Whether the Route 53 hosted zone remains as an explicitly approved persistent resource is
  deferred to the live P12 session plan review. P12.3 must record that decision and prove the
  resulting teardown or persistence state.

## Consequences

- P12 has a concrete DNS and certificate target, so local P12.1 implementation can start.
- Domain registration remains an owner-managed external prerequisite and cost; no registrar
  credentials or personal registration details enter this repository.
- The Terraform path stays disabled by default and cannot change AWS during ordinary local or
  CI validation.
- A live certificate cannot reach `ISSUED` until `bedoux.com` is delegated to the module's
  Route 53 nameservers. DNS propagation time must be included in the alarmed live-session plan.
