# ADR 0013: Remain private at P9; ADR 0004's public flip is not exercised

- Status: Accepted
- Date: 2026-08-07

Supersedes the "flip to public before P9" clause of [ADR 0004](0004-start-private-flip-public-later.md).

## Context

ADR 0004 committed to flipping `bedoux-tech/bedoux-commerce-cloud` from private to public
before P9 (the interview package), preceded by a full-history secrets sweep. P9 is now
complete and its gate is approved by the owner. At this decision point, the owner chose to
keep the repository private rather than exercise that flip.

## Decision

- The repository **remains private**. ADR 0004's "flip to public before P9" clause is
  superseded and not exercised.
- Every other part of ADR 0004 stands unchanged: hosting at `bedoux-tech`, the collaborator
  push-access model, branch discipline, and commit conventions.
- ADR 0010's local pre-push guardrail remains the operative compensating control for `main`
  protection, since GitHub's ruleset enforcement is unavailable on this private repository's
  current plan regardless of this decision.
- If the repository is made public in the future, that requires its own new ADR (not a revert
  of this one) and must be preceded by the full-history secrets/account-ID sweep ADR 0004
  already specified — that prerequisite is not waived by staying private now, only deferred
  until the flip is actually decided.

## Consequences

- No public portfolio URL exists as of P9's completion. Sharing the project (e.g., in an
  interview context) requires either a collaborator invite or a future public-flip decision.
- The no-secrets-in-history discipline continues to apply at full strength regardless of
  visibility — nothing about staying private relaxes it.
- This ADR does not reopen or change any P9 deliverable; it only records the owner's explicit
  choice on the one open item ADR 0004 left pending for this point in the project.
