# Handoff

Everything above the fenced block is reference; **paste the fenced block below into a new
Claude Code / Codex / agent session** to continue this project. Regenerate this file at every
session closeout (`/closeout`).

---

```text
Continue bedoux-commerce-cloud from
/var/home/tsogtb/git-projects/bedoux/worktrees/bedoux-commerce-cloud/raspy-lantern/bedoux-commerce-cloud.

Start with START-HERE.md, AGENTS.md, and docs/PROGRESS.md. The progress file is authoritative.
Use the active worktree/branch recorded by Git; preserve unrelated changes.

Current state as of 2026-08-20:
- P0-P10 are complete and gate-approved. P11 is active.
- P11.1-P11.5 and T-1101-T-1104 are complete. No P11 checklist item remains active; the phase
  gate awaits explicit owner approval in its own commit. P12 is not active.
- Branch p11-4-node-loss contains the two AZ-pinned one-node-group design, PDB/topology overlay,
  bounded drain/recovery helper, pinned k6 workload, and P11.4 runbook.
- ADR 0017 chose two fixed one-node Spot groups and soft one-AZ stateless failover. ADR 0018
  supersedes only its invalid minDomains clause: Kubernetes 1.34 permits minDomains only with
  DoNotSchedule, so the AWS ScheduleAnyway overlay omits minDomains.
- ADR 0019 is owner-accepted after the failed live transition: AWS-HA-only 30-second ALB target
  deregistration, 45-second API/web preStop, 60-second grace, and deterministic web target-health
  readiness-gate injection through a zero-replica bootstrap. The runtime guard fails closed if any
  part is missing. Base/kind behavior remains unchanged.
- The first live T-1103 attempt established the correct failure/recovery path but failed the
  zero-request-failure gate with 115 failures out of 30,265. ADR 0019 corrected that measured
  ALB/pod termination gap and was proven locally before the live retry.
- The 2026-08-20 reviewed AWS retry passed T-1103. One safe stateless AZ node drained in
  73.72 seconds during pinned k6 0.52.0 traffic. All 33,507 requests/checks succeeded with 0
  failures and 0 interrupted iterations; average latency was 78.24 ms, p95 155.35 ms, p99
  453.29 ms, and maximum 1.25 s. API/web recovered in the surviving AZ, PostgreSQL was untouched,
  and recovery restored both Deployments across both Ready AZ nodes. Public health/catalog and
  both ALB targets were healthy after recovery.
- The Ingress/ALB was removed first, then the app/controller/prerequisites. The guarded destroy
  plan was 0 add, 0 change, 16 destroy and removed EKS, both node groups/add-ons, access objects,
  and the no-NAT VPC. Exact temporary cluster OIDC lookup returned NoSuchEntity. The full sweep
  found zero temporary or unattached billable resources; temporary files, processes, and the k6
  container are also gone.
- Persistent allowlist only: Terraform state bucket/history, two ECR repositories, six IAM
  roles/policies, and the GitHub OIDC provider. Terraform state contains data sources only.
- Budget actual was USD 4.552 at session close with no forecast; this session is estimated below
  USD 0.30 pending billing ingestion.
- Helm profile assertions, mocked guard success/refusal paths, and pinned k6 0.52.0 p99/failure
  diagnostics pass. A fresh three-node kind drill then proved the Kubernetes termination contract:
  19,011/19,011 requests succeeded under a 48.39-second drain, with p95 670.56 ms, p99 807.89 ms,
  stateless recovery on one worker, PostgreSQL untouched, restored two-worker placement, and clean
  cluster/file teardown. The drill exposed and fixed a recovery-helper false-positive: terminating
  pods are now excluded before placement is evaluated, with at most one bounded stateless
  replacement per Deployment. The owner restored the transient host inotify limit from 1024 to
  its original 128; local closeout is complete.

Next action:
1. Owner explicitly approves or rejects the P11 phase gate. If approved, record the required
   standalone commit `Phase 11 gate approved by owner; activate Phase 12` before activating P12.
2. Do not start P12 or make its pending domain decision until that gate commit exists.

Hard boundaries: USD 20/month; ca-central-1; bedoux-admin only; no NAT Gateway; same-day teardown;
never record account IDs, secrets, or personal email addresses. Do not start P12 before P11's
gate evidence is complete and the owner explicitly approves the phase gate.
```
