# Agent Operating Rules

These instructions are canonical and tool-agnostic. They apply to Claude Code, Codex, OpenClaw,
scripts, and human operators working in this repository.

## Required workflow

1. Begin at `START-HERE.md`.
2. Treat `docs/PROGRESS.md` as the only authoritative execution state.
3. Work on one checklist item at a time. Mark it `IN PROGRESS` before changing anything.
4. Prefer small reversible changes and verify after each one.
5. Do not mark an item complete until its stated evidence exists in `docs/PROGRESS.md`.
6. Update the progress log before ending every session, even if work failed.
7. Never silently change an architecture decision. Add a new record in `docs/decisions/`
   (supersede — do not amend accepted decisions).
8. Do not start a later phase early. Phase gates require explicit owner approval, recorded
   as their own commit: `Phase N gate approved by owner; activate Phase N+1`.

## Scope and safety

- Never put secrets, tokens, private keys, AWS account IDs, or personal email addresses in
  source control, documentation, logs, evidence, or commit messages.
- **Never create or modify AWS resources outside a session opened via
  `docs/runbooks/aws-session.md`.** Obey its stop conditions without exception.
- Every AWS resource gets the standard project tags (`project=bedoux-commerce-cloud`,
  `environment=learning`).
- Prefer read-only AWS CLI commands for verification (`describe-*`, `list-*`, `get-*`).
  Mutating commands require the session runbook to be active and the owner aware.
- Steps that can only be done in the AWS web console are written as numbered, checkable
  checklists for the owner (Tsogo) to execute in the browser and report back. Do not guess
  console outcomes — wait for the owner's confirmation and record it as evidence.
- Same-day teardown is the default for every AWS session. Only resources on the
  persistent-resource allowlist in `docs/cost-guardrails.md` may survive a session.
- No NAT Gateway in the learning profile without a reviewed exception decision.
- Preserve unrelated local changes.

## Implementation conventions

- Local first: every milestone must be demonstrable locally (Compose or kind) before it is
  attempted in AWS.
- Pin tool and image versions; record them in `docs/local-tooling.md` when they change.
- Scripts support `--help` and a no-write or `--dry-run` mode before they touch AWS.
- Unit and integration tests use local fixtures and require no AWS credentials.
- Use ISO 8601 timestamps including timezone in logs and evidence.
- Commit convention: `<TaskID> complete: <what + evidence pointer>` for task completions,
  `Phase N gate approved by owner; activate Phase N+1` for gates, and an explicit
  `Fix ...` prefix for bug fixes.

## Completion standard

A phase is complete only when:

- every required deliverable exists;
- automated tests pass;
- the phase gate evidence (see `docs/TEST-PLAN.md` T-NNN ids) is recorded in
  `docs/PROGRESS.md`;
- rollback or teardown is verified where applicable — for AWS phases that means the
  teardown sweep in `docs/runbooks/aws-session.md` came back clean;
- the next phase is explicitly activated by the owner.
