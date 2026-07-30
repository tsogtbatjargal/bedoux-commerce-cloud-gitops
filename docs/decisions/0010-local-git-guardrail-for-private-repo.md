# ADR 0010: Use a local pre-push guardrail while private-repository branch protection is unavailable

- Status: Accepted
- Date: 2026-07-30

## Context

P6.3 introduced a green pull-request validation workflow and expected server-side protection
for `main`. GitHub's live API reports that rulesets for this private repository require an
eligible organization plan, while the classic branch-protection endpoint has no rule. The owner
chose to continue without changing repository visibility or purchasing a plan at this point.

ADR 0004 keeps the repository private until the pre-P9 history review; making it public now
would be an unrelated scope and safety change.

## Decision

Install `scripts/git-hooks/pre-push` in each active developer clone through
`scripts/install-git-guardrails.sh --install`. The hook rejects every direct push of local
`main`, forcing normal work onto a topic branch and through the `PR validation` workflow.

This is a compensating local control, not a substitute for GitHub server-side protection. The
runbook names its bypasses explicitly. Server-side `main` protection remains required when the
repository becomes eligible, after the P9 history review or an owner-approved plan change.

## Consequences

- The active workstation gets a hard, testable local block against accidental direct pushes to
  `main` at no additional GitHub cost.
- The control does not cover other clones, GitHub's web UI, or deliberate local hook removal;
  the project must never claim that `main` is server-protected while this ADR is active.
- PR #1's four green checks provide real automated validation evidence, but GitHub cannot yet
  require them before a merge.
- A future server-side rule supersedes this ADR with a new record; ADR 0004's private-until-P9
  decision remains unchanged.
