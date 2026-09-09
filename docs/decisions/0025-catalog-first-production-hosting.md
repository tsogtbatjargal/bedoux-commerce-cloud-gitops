# ADR 0025: Start bedoux.ca with a static catalog hosting profile

- Status: Proposed
- Date: 2026-09-08
- Related assessment: [production-hosting-plan.md](../production-hosting-plan.md)
- Supersession: none while Proposed. If accepted, replaces ADR 0022's ALB/regional-certificate
  choice only for the new persistent catalog profile; P12's historical learning profile remains
  valid. Retains bedoux.ca, www, Route 53 delegation and the decision to retire Shopify.

## Context

The owner completed P0–P14, maintenance and housekeeping, then authorized a planning-only
production-hosting assessment. Existing EKS infrastructure is designed for bounded learning
sessions. Its production target is too expensive under the USD 20 monthly account limit.
The current React app depends on a live API, and the order routes lack customer authorization
and payment integration. Serving the current build from static storage would not by itself work.

The first-release assumption is a useful public catalog with no real orders or private data.
The owner has not yet accepted that scope, the hosting option or new persistence rules.

## Proposed decision

Introduce a distinct catalog-only profile: React plus a validated public content snapshot,
served from private S3 in Canada Central through CloudFront. Use bedoux.ca as canonical and
redirect www to it. Adapt the frontend so it needs no live API, cart or checkout for this release.
Preserve the existing backend and learning deployment for their documented purposes.

Evaluate the CloudFront Free pricing plan against the required cache, routing, monitoring and
automation contracts before deployment. If it cannot satisfy them, return for a revised decision;
do not automatically switch to a paid tier or pay-as-you-go. See the assessment's dated
[cost comparison](../production-hosting-plan.md#monthly-cost-comparison) for inputs and caveats.

Use a CloudFront viewer certificate in `us-east-1`; the current regional ALB certificate is
not reusable there. This needs a narrow approved region exception, with public content cached
globally. [AWS certificate requirements](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cnames-and-https-requirements.html).

Before live work, adopt explicit persistent-hosting rules, production tags, an isolated state
root, exclusive ownership of DNS aliases, a retained-resource allowlist and an operator runbook.
Keep the USD 20 cap and current learning teardown policy unless the owner separately changes
them. Do not share a destroy boundary with session infrastructure.

## Alternatives

- A single Lightsail VM best preserves the current runtime but introduces patching and database
  recovery duties, a single failure domain and little budget headroom.
- A VM with encrypted managed PostgreSQL costs more and still needs application security work.
- Continuously running EKS exceeds the budget even before worker and data-service costs.

## Consequences

The public website can launch independently of transactional-store development. Content updates
become reviewed releases with recoverable artifacts; no customer-write recovery is needed yet.
Static mode, release routing, cache behavior, owner notification and rollback are new work and
must be demonstrated locally before a bounded live session.

The Free plan provides no uptime SLA; this proposal makes no customer-facing availability
guarantee. [CloudFront plan pricing](https://aws.amazon.com/cloudfront/pricing/).
Product content, accessibility and the eventual commerce roadmap still need owner decisions.
The assessment's engineering and recovery estimates are proposals, not measured production results.

## Acceptance boundary

This ADR remains Proposed until the owner selects the launch scope and accepts the decision.
No accepted ADR text, current resource tags, budget, persistence rule or deployment behavior is
changed here. PH-1 must reconcile those operating documents before a live session can be opened.
ADR acceptance alone does not approve implementation, saved-plan apply or DNS cutover.
