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

- Moving to another computer: use the portable prompt and 12-file manifest in `docs/HANDOFF.md`.
  The owner authorized consolidating the published planning package into `main` via checked PRs.
  Verify the merge checkpoint, then use updated `main`; the temporary feature branch may be
  removed after merge. No implementation is activated and ADRs 0025/0026 remain Proposed.
- P0–P14 and T-001–T-1404 are complete and gate-approved. A separate owner-authorized
  production-hosting assessment (PH-A, planning only) is prepared for review; see
  `docs/PROGRESS.md` for its evidence and state.
- P14 closeout: PR #66 merged the focused P14 reconciliation and standalone owner gate commit to
  `main` as `9a2fe597f79018a68bfbe53580acebf8d91b0248`.
- Post-P14 maintenance track (M1–M5, owner-approved, explicitly not P15) is also **complete**:
  M1 Helm render validation (`521f3a3`), M2 shared canary pod spec / ADR 0024 (`83b2eaa`), M3
  named deployment profiles (`ff81bfc`), M4 typed P12/P13 gate diagnostics (`38cadaf`), M5 lazy
  `app.db` engine + isolated order pricing (`4e63213`), plus `docs/verification-lessons.md`
  (`950775b`). Final merge: `40bb39d`.
- GO-A GitOps planning deliverable is prepared for review; no implementation phase is active.
  Post-track housekeeping H1–H6, P0–P14 and M1–M5 remain complete.
- H6 closeout: exact head `e207efc` passed all four jobs in PR-validation run
  `34163029641` and merged through PR #84 as `0635b35`; its merged local/remote branch and
  worktree were removed.
- Last recorded AWS state (not rechecked by PH-A): no temporary or hourly billed project resource
  is live. Only the owner-approved
  persistent ECR/IAM, Route 53/ACM, and Terraform state-storage allowlist remains; website aliases
  are absent.
- Local state: no kind cluster, Bedoux kind node/PVC volume, kind network, or `kind-bedoux`
  kubeconfig entry remains. The host inotify setting is restored to 128. Historical EKS contexts
  remain with no current context selected; always choose an explicit context before Kubernetes
  work.
- Next action: review `docs/gitops-expansion-plan.md`, Proposed ADR 0026 and
  `docs/runbooks/gitops-recovery.md`. The interview choices are recorded; GO-1–GO-8 remain
  NOT STARTED. GO-1 is the next eligible design-contract task after explicit activation.
  Hosting implementation is deferred; PH-1–PH-5 stay NOT STARTED and ADR 0025 remains Proposed.

## Evidence map

- `docs/gitops-expansion-plan.md` — GO-A review package: agreed two-repository flow, migration
  design gates, GO-1–GO-8 acceptance evidence and operating boundaries.
- `docs/runbooks/gitops-recovery.md` — proposed automatic traffic abort and separate reviewed
  Git repair, data recovery, restart safeguards and teardown suspension.
- `docs/production-hosting-plan.md` — PH-A hosting options, dated costs, application gaps,
  proposed implementation sequence and review decisions for bedoux.ca.
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
- `docs/verification-lessons.md` — concrete verification failures and the practices that closed
  them; read before adding or changing a test or CI check.
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

The post-P14 M1–M5 maintenance checks are also locally runnable from the repository root:

```text
# M1/M2: named Helm render contracts and shared stable/canary pod-spec parity
toolbox run -c bedoux-aws /usr/bin/make helm-test

# M3: all 256 legacy deployment-input combinations match the named-profile resolver
python3 scripts/test_deploy_profile.py

# M4: all typed P12/P13 gate-result fixtures and error channels
python3 scripts/test_gate_checks.py

# M5: isolated pricing and database-credential boundary (API dev dependencies required)
(cd apps/api && python3 -m pytest -q tests/test_pricing.py tests/test_database_credentials.py)
```

These are local, read-only checks. The M5 command assumes `apps/api`'s `.[dev]` dependencies are
installed in the active Python environment; CI runs the full API suite against its own ephemeral
PostgreSQL service.

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
