# Start Here

This file is the entry point for a new Claude Code, Codex, OpenClaw, or human session.

## First actions

1. Read `AGENTS.md` completely.
2. Read the overall status and newest session entry in `docs/PROGRESS.md`; that file is the only
   authoritative execution state.
3. Run `git status --short` and `git log --oneline -5`.
4. If one checklist item is explicitly `IN PROGRESS`, read only its section in
   `docs/IMPLEMENTATION-PLAN.md` and the decisions/tests/runbooks it references.
5. If no item is active, stop. Do not infer a new phase or begin implementation from an old plan,
   runbook, branch, or historical session-log entry.

## Current checkpoint

- Repository state: **COMPLETE**. P0–P14 and T-001–T-1404 are complete and gate-approved.
- Final closeout: PR #66 merged the focused P14 reconciliation and standalone owner gate commit
  to `main` as `9a2fe597f79018a68bfbe53580acebf8d91b0248`.
- Active phase/task: **none**. The owner closed the P10–P14 optimization track and explicitly did
  not activate P15 or another unplanned phase.
- AWS state: no temporary or hourly billed project resource is live. Only the owner-approved
  persistent ECR/IAM, Route 53/ACM, and Terraform state-storage allowlist remains; website aliases
  are absent.
- Local state: the retained Calico-backed kind node is stopped with its PVC preserved; the host
  inotify setting is restored to 128. A default kubeconfig may point to a deleted EKS endpoint, so
  always select an explicit context before Kubernetes work.
- Next action: safe stop. Future implementation requires a new owner-approved scope and explicit
  activation of its first checklist item.

## Evidence map

- `docs/PROGRESS.md` — authoritative checklist, AWS teardown evidence, and chronological session
  record.
- `docs/IMPLEMENTATION-PLAN.md` — delivered P0–P14 plan; historical, not future authorization.
- `docs/TEST-PLAN.md` — T-001–T-1404 acceptance definitions.
- `docs/decisions/README.md` — ADR status and supersession index.
- `docs/interview/walkthrough-script.md` — measured 15-minute technical walkthrough.
- `docs/architecture.md` and `docs/diagrams/` — implemented paths, bounded learning profiles,
  and production-target distinctions.
- `docs/p10-p13-cost-report.md`, `docs/resource-right-sizing.md`, and
  `docs/spot-diversification.md` — P14 capstone evidence.
- `docs/runbooks/aws-session.md` — mandatory guardrail for any future AWS resource mutation.

## Completion verification

From the repository root:

```text
toolbox run -c bedoux-aws /usr/bin/make docs-check
scripts/test-p14-resource-right-sizing.sh
scripts/test-p14-spot-diversification.sh
scripts/test-p14-cost-report.sh
scripts/test-p14-interview-package.sh
git diff --check
```

These checks verify the final documentation/action pins and P14 evidence. They do not authorize a
new phase or contact AWS/Kubernetes endpoints.

## Non-negotiable boundaries

- Hard AWS budget cap: **USD 20 per month**. The stop conditions in
  `docs/runbooks/aws-session.md` override any task.
- Never create or modify AWS resources outside an owner-authorized session opened through that
  runbook. Same-day teardown is the default.
- After an AWS session, verify the resource inventory empty except for the persistent allowlist in
  `docs/cost-guardrails.md`.
- Never commit secrets, tokens, private keys, AWS account IDs, personal email addresses, or raw
  identity output.
- Use `ca-central-1`, the `bedoux-admin` profile, standard project tags, and no NAT Gateway unless
  a reviewed decision explicitly supersedes those constraints.
- Demonstrate milestones locally before AWS and never claim customers, uptime, traffic, or other
  production traits the system has not had.
- Preserve unrelated local changes; never push `main` directly.

## Resume after a disconnect

1. Re-read the current status and newest entry in `docs/PROGRESS.md`.
2. Inspect Git status and recent history.
3. If AWS work might have been in flight, run the read-only leftover sweep from
   `docs/runbooks/aws-session.md` before anything else.
4. Reconcile discrepancies in `docs/PROGRESS.md`; never infer completion or teardown.
5. Continue only an explicitly active item. Otherwise stop and request owner direction.
