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

- Owner direction (2026-09-10): the narrowly scoped local-only GitOps scaling MVP is
  **closed out** — DEF-012–014 fixed and demonstrated, PR #91 (`feature/gitops-mvp` →
  `main`) carries all MVP changes with all four CI checks green, merged per explicit owner
  authorization (see `docs/PROGRESS.md` session log for the merge SHA).
- Owner direction (2026-09-10, same day, later): a second **bounded post-MVP milestone,
  GO-MVP-U1**, was activated and completed on isolated worktree `../bedoux-gitops-update`
  (branch `feature/gitops-version-update`, from `main` at `f3e38bd`) — DEF-015's startup
  inventory-error branch hardened, a real version A→B application update live-demonstrated with
  a surviving synthetic order, migration ordering plus a controlled migration failure/recovery
  live-demonstrated, its verifier hardened across four Codex review rounds (35/35 mock
  assertions in the final round), and the evidence packaged in
  `docs/runbooks/gitops-mvp-demo.md`'s "GO-MVP-U1" section and `docs/PROGRESS.md`'s
  2026-09-10T14:45:00-06:00 session log entry. **PR #92 (`feature/gitops-version-update` →
  `main`) was merged by explicit owner authorization on 2026-09-10T21:37:35-06:00 at reviewed
  head `935b95cc7cacd49c1b86e4676b5644069ec038d1`, producing merge commit
  `b7e52a9a14f2366609e6e733df0277872a5439b5` — GO-MVP-U1 is complete and merged.** Full GO-1 and
  the remaining advanced GitOps backlog (DEF-001–011, DEF-015 subfinding 3, DEF-016) remain
  explicitly deferred — not activated by either milestone or its merge. Read
  `docs/DEFERRED-WORK.md` for unfinished findings, safe interim boundaries and revisit criteria;
  update it whenever additional work is deferred. Neither milestone marks the full GO-1 contract
  complete, activates GO-2, or bypasses the explicit implementation gate in `docs/PROGRESS.md`.
- **Checkpoint-commit convention correction (2026-09-14):** a prior session's PROGRESS.md entry
  wrongly described a direct push of a checkpoint-only commit to `main` (`f290478`, reconciling
  PR #92's merge SHA) as matching an "established convention" set by an earlier direct-to-main
  checkpoint commit (`f3e38bd`, after PR #91). Both were mistaken: `AGENTS.md`'s PR workflow and
  this file's own "Non-negotiable boundaries" section ("never push `main` directly") were not
  actually superseded by either commit sitting on `main`'s history — a commit existing on `main`
  is not itself authorization to keep doing that. The historical commits are NOT rewritten (the
  append-only session log is corrected in place with a note, not deleted — see
  `docs/PROGRESS.md`'s session log for the correction entry). **Every future checkpoint or
  documentation change, including routine post-merge reconciliation, goes through a feature
  branch and a reviewed PR — no exceptions for "just a checkpoint update."**
- Continuation target: `nomad`, app clone
  `/var/home/tsogtb/src/github.com/bedoux-tech/bedoux-commerce-cloud`. Read-only verification
  initially found it stale at `0c1c285`; the authorized update after PR #89 brought it cleanly
  to `90a7f26`. Receive the subsequent synchronization closeout too. The proposed sibling
  `bedoux-commerce-env` directory is absent; creation remains GO-2 work. HANDOFF and
  local-tooling record setup checks and owner permission for bounded Claude subagents.
- Moving to another computer: use the portable prompt and 12-file manifest in `docs/HANDOFF.md`.
  PR #87 merged the planning package into `main` as `e40912d` with all four exact-head checks
  green; PR #86's toolchain is included. Both old feature branches are removed. Use updated
  `main` including the closeout checkpoint; no implementation or ADR acceptance is implied.
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
- GO-1 status: the owner explicitly activated GO-1 on 2026-09-09 and it is **reopened for
  correction a third time** (not complete, not not-started) after three independent review rounds
  (Codex, `docs/PROGRESS.md` session log entries 2026-09-09T11:03:16-06:00,
  2026-09-09T13:29:08-06:00 and 2026-09-09T14:37:25-06:00) found and closed real defects: a
  suspend script that returned success under total command failure and later under an incomplete
  Application response; a rejected-release predicate that could be bypassed and later a
  first-bootstrap contradiction; binding evidence missing repository-identity validation; a
  read-only precondition check that could not prove nothing had run; and a paired-Rollout
  coordination design that did not preserve its own stated abort contract. Read
  `docs/gitops-go1-design-contract.md` and its "Corrections applied" sections (all three rounds)
  before touching any GO-1 artifact. ADR 0026 and new Proposed ADR 0027 remain Proposed.
  GO-2–GO-8 remain NOT STARTED; GO-2 requires its own separate explicit owner activation, not
  implied by GO-1 progress. Unrelated and not fixed by GO-1's work: `make docs-check` fails on a
  missing `docs/diagrams/gitops-workflow.svg` export for an untracked, in-progress diagram —
  preserved untouched, not this session's scope.
- Next action: review `docs/gitops-expansion-plan.md`, Proposed ADR 0026, ADR 0027 and
  `docs/runbooks/gitops-recovery.md`. Hosting implementation is deferred; PH-1–PH-5 stay
  NOT STARTED and ADR 0025 remains Proposed.

## Evidence map

- `docs/gitops-expansion-plan.md` — GO-A review package: agreed two-repository flow, migration
  design gates, GO-1–GO-8 acceptance evidence and operating boundaries.
- `docs/runbooks/gitops-recovery.md` — proposed automatic traffic abort and separate reviewed
  Git repair, data recovery, restart safeguards and teardown suspension.
- `docs/production-hosting-plan.md` — PH-A hosting options, dated costs, application gaps,
  proposed implementation sequence and review decisions for bedoux.ca.
- `docs/PROGRESS.md` — authoritative checklist, AWS teardown evidence, and chronological session
  record.
- `docs/DEFERRED-WORK.md` — maintained backlog for unfinished work and post-MVP improvements;
  revisit after the MVP and at milestone closeouts, not a second execution checklist.
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
