# Start Here

This file is the entry point for a new Claude Code, Codex, OpenClaw, or human session.

## First five actions

1. Read `AGENTS.md` completely.
2. Read `docs/PROGRESS.md` completely. It is the authoritative checkpoint.
3. Read the active phase in `docs/IMPLEMENTATION-PLAN.md`.
4. Read only the architecture, decision, test, or runbook sections referenced by that phase.
5. Before changing anything, verify the last completed checkpoint using the commands recorded
   in `docs/PROGRESS.md`.

Do not infer progress from files merely existing. A task is complete only when its checkbox is
checked in `docs/PROGRESS.md` and its evidence is recorded in the session log.

## Current checkpoint

- Project state: **Phase 0 (bootstrap) in progress — doc spine, git repo, and agent config
  being created (2026-07-17).**
- Active phase: **P0 — Bootstrap.**
- Next action: **finish P0 checklist in `docs/PROGRESS.md`, then P1.1 — install and pin the
  local toolchain until `make tools-check` is green.**
- Safe stopping point: after any single task with its evidence recorded in `docs/PROGRESS.md`.
- Standing gate: `make docs-check` must pass before any commit that touches docs or diagrams.

## Non-negotiable boundaries

- Hard AWS budget cap: **USD 20 per month.** Stop conditions in
  `docs/runbooks/aws-session.md` override any task in progress.
- **No AWS resource is created or modified outside a session opened via
  `docs/runbooks/aws-session.md`.** Same-day teardown is the default.
- After every AWS session the resource inventory must be verified empty except for the
  persistent-resource allowlist in `docs/cost-guardrails.md`.
- No secrets, tokens, private keys, AWS account IDs, or personal email addresses in this
  repo, its history, logs, or evidence.
- The AWS region is pinned once chosen (recorded in `docs/PROGRESS.md` known facts); never
  infer it from a console URL.
- Every milestone is demonstrated locally (Compose or kind) before it is attempted in AWS.
- Never claim production traits (traffic, uptime, customers) the system has not had.

## Resume protocol after a disconnect

1. Run `git status --short` and `git log --oneline -5`.
2. Inspect the latest entry in `docs/PROGRESS.md`.
3. Re-run the latest recorded verification command.
4. If AWS work was possibly in flight: run the read-only leftover sweep from
   `docs/runbooks/aws-session.md` (or `/aws-teardown-verify`) before anything else —
   an orphaned cluster costs money every hour.
5. If verification disagrees with the progress log, stop and record the discrepancy. Do not
   advance the phase.
6. Continue only the single item marked `IN PROGRESS`.
7. Before stopping, update the checklist and append a dated session entry, even if work failed.

## Definition of a useful session log entry

Record:

- date/time and agent/operator name;
- phase and task ID;
- files or systems changed;
- commands/tests run and their result;
- **AWS resources created and destroyed this session, and the estimated session cost**
  (write `AWS: none` when the session never touched AWS);
- decisions made, without including secrets;
- exact next action;
- blockers and safe rollback, if applicable.
