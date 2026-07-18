---
description: Report current project state, last evidence, and next action; verify PROGRESS is not stale
---

Catch the operator up on bedoux-commerce-cloud. Do exactly this:

1. Read `START-HERE.md`, `docs/PROGRESS.md` (overall status + latest session log entry), and
   the active phase in `docs/IMPLEMENTATION-PLAN.md`.
2. Run read-only staleness checks and compare with what PROGRESS claims:
   - `git status --short` and `git log --oneline -5`
   - `make docs-check`
   - if AWS credentials are configured (`aws sts get-caller-identity` succeeds):
     `aws eks list-clusters` and `aws elbv2 describe-load-balancers` — anything live must
     match the "AWS resources currently live" row in PROGRESS.
3. Report, in plain prose: current phase and task, the last completed item with its evidence,
   any discrepancy between PROGRESS and reality (a discrepancy is a blocker — do not proceed
   past it), and the exact next action.

Do not change any files. This command is read-only.
