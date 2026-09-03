# Handoff

Everything above the fenced block is reference; **paste the fenced block below into a new
Claude Code / Codex / agent session** to continue this project. Regenerate this file at every
session closeout (`/closeout`).

---

```text
Continue bedoux-commerce-cloud from
/var/home/tsogtb/git-projects/bedoux/worktrees/bedoux-commerce-cloud/raspy-lantern/bedoux-commerce-cloud.

Start with START-HERE.md, AGENTS.md, and docs/PROGRESS.md. The progress file is authoritative.
Use the active worktree/branch recorded by Git and preserve unrelated changes.

Current state as of 2026-09-02T17:31:18-06:00:
- P0–P14 are complete and gate-approved. The owner closed the P10–P14 optimization track and
  explicitly instructed that no unplanned phase be activated.
- P14.1/T-1401 is complete locally. Real P11 Metrics Server samples support increasing only the
  API CPU limit from 250m to 500m. Requests and values without retained measurements remain
  unchanged; the calculation and rollback are in `docs/resource-right-sizing.md`. The corrected
  deployment-scoped test checks stable/canary inheritance and rejects a deliberately divergent
  canary fixture.
- Focused PR #61 targeted `main` at exact head `3f547a1`; all four jobs passed in run
  `33559670780`, and it merged as `fd4cabb`. Its publication branch was deleted after merge.
- P14.2/T-1402 is complete at merged commit `bdc5b1e` through PR #62 (`758a087`). The owner-approved
  Terraform plan applied the wildcard `*` lifecycle rule to both persistent ECR repositories. A
  real bare commit-SHA push was retained among the newest ten in both lifecycle previews; twelve
  older tagged images per repository were marked `EXPIRE`. The temporary verification tags and all
  session artifacts were removed. P14.3 is complete locally at focused commit `0edafc9` from
  merged P14.2: same-shape `t3.medium`/`t3a.medium` Spot pools preserve the one-node and two-node
  HA ceilings. The review records managed-node Capacity Rebalancing, ordinary-profile
  30-second/no-preStop shutdown behavior, and ADR 0019's AWS-HA exception. All five Terraform
  tests pass. Exact head `0edafc9` passed all four jobs in run `33584953985` and merged through
  PR #63 as `aed6f5d`.
- P14.4/T-1403 is complete at focused commit `511bf24`, based on exact prior merged `main`
  `aed6f5d`. `docs/p10-p13-cost-report.md` records USD 4.939738 of conservative P10-P13-window
  usage, final August whole-account usage of USD 8.373571 (41.9% of the USD 20 cap), September
  through day one at USD 0.501845 estimated, dominant services, credits, and daily-attribution
  limitations. Its CI-wired test sums the tables, enforces the cap, and rejects an inflated
  fixture. All four jobs passed in run `33652892894`; PR #64 merged the exact head as `a8e9276`,
  and checkpoint reconciliation `fab61a6` contains that merge.
- P14.5/T-1404 is complete locally at focused commit `e165332`, based on merged `main` `a8e9276`.
  The walkthrough extends the P9 story with P10–P14 evidence, measures 1,289 spoken words, and fits
  13:53 at 100 wpm including overhead. A seventh optimization-track pair and refreshed
  system-context/request-path/CI-CD pairs are visually clean; semantic and `docs-check` gates pass.
  Independent review accepted the exact commit after reproducing timing arithmetic, fail-sensitive
  checks, evidence traceability, diagram renders, CI wiring, and leakage checks. Exact commit
  `e165332` passed all four jobs in exact-head run `33681885076` and merged through owner-approved
  PR #65 as `80cd24c`. Checkpoint reconciliation `4286baa` contains the verified merge.
- P13.1/T-1301 and P13.2/T-1302 passed their live AWS gates. The successful blocked-canary run
  proved real ALB 90/10 staging, public and direct injected-error correlation, promotion blocked,
  reconciled 100/0 rollback, stable-only cleanup, and final public health/catalog recovery.
- P13 teardown completed in the required order. The owner-approved temporary-only destroy plan
  removed 18 resources, the temporary cluster OIDC provider is absent, the authoritative AWS
  inventory sweep is clean, and exact session artifacts were removed from `/tmp`.
- No temporary or hourly billed AWS resource is live. Only the approved persistent ECR/IAM,
  Route 53/ACM, and Terraform state-storage allowlist remains. Website aliases remain absent.
- The owner approved the P13 gate on 2026-09-01 in standalone commit `8920173`, activating P14.
- The active local checkpoint branch is `p14-1-resource-right-sizing`; reconciliation commit
  `4286baa` contains current `origin/main` `80cd24c`, and the standalone P14 gate checkpoint follows
  it. Local `main` may be stale; never push `main` directly.
- ADR 0023 is Accepted. It keeps one Helm release and implements opt-in stable/canary API+web
  pairs, weighted routing, exact image and target-health gates, ALB pod-readiness, reconciled
  promotion/abort, bounded drain, and stable-only cleanup.
- The final P13.2 attempt exposed one durable operational lesson: an AZ-bound PostgreSQL EBS
  volume can block recovery when the only Spot worker is replaced into another AZ. The successful
  bounded recovery temporarily added a worker in the volume's AZ without deleting the PVC, then
  teardown removed both workers and the volume.
- Long Terraform mutations must retain a resumable process/session handle and private log, poll
  to a real exit status, and never infer completion from a disconnected output stream. The
  hardened destroy helper accepts Terraform's null no-op JSON and protects plan/OIDC files as
  mode 0600.
- The retained local Calico-backed kind node is stopped with its PVC preserved. The host
  `fs.inotify.max_user_instances` value is restored to 128. The default kubeconfig can point to a
  deleted EKS endpoint, so always select an explicit context.

Next action:
1. Stop safely; there is no active phase or checklist item.
2. Before future implementation, the owner must approve a new scope and explicitly activate its
   first checklist item. Do not infer a P15 or other continuation.

Hard boundaries: USD 20/month; ca-central-1; bedoux-admin only; no NAT Gateway; same-day teardown;
never record account IDs, secrets, personal email addresses, or registrar details.
```
