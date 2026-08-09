# ADR 0014: Post-P9 optimization track — scope and guardrail interactions

- Status: Accepted
- Date: 2026-08-09

## Context

P0–P9 are complete; the P9 gate was approved by the owner on 2026-08-07, and
`docs/PROGRESS.md` records the project as complete with the explicit rule that any further
work "starts with its own new task/ADR, not a reopening of P0–P9." The owner has now asked for
the working prototype to be optimized and improved, prioritizing reliability/HA, security
hardening, delivery maturity, and performance/cost — under the same operating model as before.

Several of the natural optimization moves collide with existing hard limits in
`docs/cost-guardrails.md`:

- "unbounded node or pod autoscaling" is prohibited outright;
- "Multi-AZ RDS during routine learning sessions" is prohibited outright;
- a Route 53 hosted zone is only pre-approved as a persistent resource "if a domain is
  intentionally enabled" — i.e. it still needs its own explicit decision.

This decision records how the new P10–P14 track (`docs/IMPLEMENTATION-PLAN.md`) reads those
limits, so no future session has to re-derive the interpretation mid-work.

## Decision

- This track is **additive**. P0–P9's completion, their recorded evidence, and ADR 0013's
  "remain private" decision are not reopened or re-litigated by any P10–P14 work.
- **Bounded vs. unbounded autoscaling:** an HPA (or Cluster Autoscaler / nodegroup scaling
  config) with an explicit, hard-coded `maxReplicas` / max-node ceiling satisfies the
  guardrail. "Unbounded" means no ceiling at all, not "any autoscaling." P11's HPA work must
  always ship with an explicit cap in the same commit that enables it.
- **Multi-AZ RDS** is never run as a routine, repeatable learning session. If P11 or a later
  phase wants to demonstrate Multi-AZ failover, it is a single, time-boxed, explicitly
  reviewed one-off — the same treatment the original plan already gives NAT Gateway
  exceptions — proposed and approved in its own session-start note before it happens, then
  torn down same-day like everything else. Absent that explicit one-off review, RDS stays
  Single-AZ as it is today.
- **Route 53 / custom domain**: deferred to P12. Before P12.1 starts, the owner must choose
  one of: buy a new domain (a small recurring cost outside the AWS budget), use a subdomain of
  a domain already owned, or skip live deployment and leave the Terraform module
  written-but-unapplied (mirroring how TLS itself was deferred by ADR 0002). Whichever is
  chosen is recorded either as an update to this ADR or a new dedicated ADR — not assumed.
- Every AWS-costing item introduced by P10–P14 remains session-based with same-day teardown,
  per `docs/cost-guardrails.md`, unless explicitly added to the persistent-resource allowlist
  the same way ECR repos and the Terraform state bucket already are.

## Consequences

- Future sessions working P10–P14 can implement bounded autoscaling without pausing to ask
  whether it's allowed — it is, as long as the cap ships with it.
- P11's Multi-AZ RDS ambitions (if any) are capped to a single reviewed demonstration, not a
  standing feature — this avoids silently drifting into a prohibited routine cost.
- P12 cannot start until the owner has actually answered the domain question; a session must
  not assume "buy a domain" by default.
- Nothing about this ADR changes cost-guardrails.md itself — it only interprets it for the new
  track. If a future phase needs an actual guardrail change (e.g. raising the monthly cap),
  that is a separate decision, not implied here.
