# Handoff

Everything above the fenced block is reference; **paste the fenced block below into a new
Claude Code / Codex / agent session** to continue this project. Regenerate this file at every
session closeout (`/closeout`).

---

```text
Continue bedoux-commerce-cloud from
/var/home/tsogtb/git-projects/bedoux/bedoux-commerce-cloud.

Start with START-HERE.md, AGENTS.md, and docs/PROGRESS.md. The progress file is authoritative.
Use the active worktree/branch recorded by Git; preserve unrelated changes.

Current state as of 2026-08-18:
- P0-P10 are complete and gate-approved. P11 is active.
- P11.1, P11.2, P11.3, and P11.5 are complete. P11.4 is the only active item.
- Branch p11-4-node-loss contains the two AZ-pinned one-node-group design, PDB/topology overlay,
  bounded drain/recovery helper, pinned k6 workload, and P11.4 runbook.
- ADR 0017 chose two fixed one-node Spot groups and soft one-AZ stateless failover. ADR 0018
  supersedes only its invalid minDomains clause: Kubernetes 1.34 permits minDomains only with
  DoNotSchedule, so the AWS ScheduleAnyway overlay omits minDomains.
- ADR 0019 is owner-accepted after the failed live transition: AWS-HA-only 30-second ALB target
  deregistration, 45-second API/web preStop, 60-second grace, and deterministic web target-health
  readiness-gate injection through a zero-replica bootstrap. The runtime guard fails closed if any
  part is missing. Base/kind behavior remains unchanged.
- The first live T-1103 attempt established a healthy two-AZ baseline, safely drained only the
  non-PostgreSQL node, recovered API/web in the surviving AZ, and restored cross-AZ placement.
  It did not pass: k6 recorded 115 failed requests out of 30,265 (0.37%), although p95 was
  157.99 ms. Do not mark P11.4 or T-1103 complete.
- The 2026-08-18 AWS session recovered and tore down cleanly. The final sweep exposed an older
  unattached 1 GiB gp3 PostgreSQL PVC from 2026-08-11; the owner explicitly approved deleting
  that exact orphan, and the post-delete sweep found no temporary/unattached billable resources.
- Persistent allowlist only: Terraform state bucket/history, two ECR repositories, six IAM
  roles/policies, and the GitHub OIDC provider. Terraform state contains data sources only.
- Budget actual was USD 4.428 at session start; the short session was estimated below USD 0.20.
- Helm profile assertions, mocked guard success/refusal paths, and pinned k6 0.52.0 p99/failure
  diagnostics pass. A fresh three-node kind baseline later reached Ready, with API/web split across
  both workers, but no load/fault ran: blocked tool calls overran the 20:45 alarm. The exact cluster
  and archives were deleted by 21:05. This is not pass evidence; host inotify restoration to 128
  still awaits owner confirmation.

Next action:
1. Owner restores `fs.inotify.max_user_instances=128` and confirms it.
2. In a fresh independently alarmed window with enforced command timeouts, prove the 45-second
   termination hold, request continuity, recovery, and clean local teardown.
3. Keep P11.4 IN PROGRESS. Any T-1103 retry requires a fresh aws-session runbook boundary,
   independent alarm, current billing/inventory, exact Terraform plan review, separate apply
   authorization, recovery, and same-session teardown.

Hard boundaries: USD 20/month; ca-central-1; bedoux-admin only; no NAT Gateway; same-day teardown;
never record account IDs, secrets, or personal email addresses. Do not start P12 before P11's
gate evidence is complete and the owner explicitly approves the phase gate.
```
