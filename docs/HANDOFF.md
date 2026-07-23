# Handoff

Everything above the fenced block is reference; **paste the fenced block below into a new
Claude Code / Codex / agent session** to continue this project. Regenerate this file at every
session closeout (`/closeout`).

---

```text
You are continuing work on bedoux-commerce-cloud at
/var/home/tsogtb/git-projects/bedoux/bedoux-commerce-cloud — a long-running, agent-agnostic
AWS EKS commerce learning project with a hard USD 20/month budget. Owner-confirmed
optimization target: this is an EKS/platform-engineering portfolio (operational evidence —
drills, rollback, IAM — outranks commerce-app features whenever the two compete for time).

## First actions
1. Read START-HERE.md, then AGENTS.md, then docs/PROGRESS.md (the only authoritative state).
2. Verify the last checkpoint before changing anything.
3. Check docs/IMPLEMENTATION-PLAN.md's "Pending owner-approved decisions" section —
   several design decisions for later phases (P5/P6/P7) are already made and recorded but
   deliberately not yet implemented; do not miss or re-litigate them when those phases open.

## Current state (as of 2026-07-23)
- Phases 0-3 complete, gates approved. Local app (FastAPI + Postgres + React) proven on
  Compose (P2), then on kind with plain manifests (P3.1), probes/limits/Secret-vs-ConfigMap
  split (P3.2), ingress-nginx routing (P3.3), a Helm chart at charts/bedoux/ (P3.4, per
  ADR 0005), and four real drills — scale, pod deletion, a broken-config incident diagnosed
  from kubectl output alone, and rollback (P3.5). The kind cluster `bedoux` is left running.
  charts/bedoux/ is the live deployment artifact; k8s/*.yaml is P3.1-P3.3's historical
  record only.
- Real-browser verification is wired up: Playwright MCP attached via --cdp-endpoint to an
  actual Google Chrome (Flatpak, throwaway profile at /tmp/chrome-mcp-profile), not a
  bundled Chromium. That Chrome instance must be relaunched after any session/host restart:
  `flatpak run com.google.Chrome --remote-debugging-port=9222 --user-data-dir=/tmp/chrome-mcp-profile`
  (see docs/local-tooling.md).
- Rootless-Podman + kind cgroup delegation is fixed and documented; kind commands still need
  wrapping in `systemd-run --user --scope --slice=app.slice -p Delegate=yes` if run from a
  shell that isn't already under app.slice (docs/local-tooling.md explains why and how to
  check).
- Phase 4 (AWS account readiness) in progress: P4.1-P4.3 complete — root MFA enabled, root
  has zero access keys, working identity is non-root IAM user `bedoux-admin`
  (PowerUserAccess + a custom policy scoped to IAM actions on bedoux-*-named resources
  only, not AdministratorAccess), region pinned to ca-central-1. USD 20 monthly budget
  (80%/100% alerts) + Cost Anomaly Detection live (P4.2). Every AWS command in this project
  uses `--profile bedoux-admin`, never root or default. Account ID is never written to this
  repo or its history.
- P4.4 (paper rehearsal of the session runbook) is in progress or just completed — check
  docs/PROGRESS.md's latest session log entry for the exact state and any findings from
  that rehearsal (e.g. Cost Explorer needs ~24h to ingest data on a brand-new account).
- No billable AWS resources exist yet anywhere. First real cluster creation is P5.

## Locked decisions (do not revisit without a new ADR in docs/decisions/)
- ADR 0001: small stack — React/Vite/TS, FastAPI, PostgreSQL, image-storage adapter boundary.
- ADR 0002: MVP defers Route53/ACM (use ALB DNS, HTTP), RDS (in-cluster Postgres until P7),
  S3 images and Secrets Manager (P7). No NAT Gateway in the learning profile.
- ADR 0004 (supersedes 0003): private repo at bedoux-tech, flip public before P9 after a
  full-history secrets sweep; direct-to-main until P6; commit convention
  `<TaskID> complete: ...` and gate commits.
- ADR 0005: DB migrations run as a Helm post-install,pre-upgrade hook Job (corrected
  same-day from an initial pre-install design that would have failed every fresh install —
  see the ADR's correction note); no auto-downgrade on rollback; seed is a separate opt-in
  Job, never on by default.
- Four more decisions made but deliberately not yet implemented — see
  docs/IMPLEMENTATION-PLAN.md's "Pending owner-approved decisions": Helm migration hook
  design is done (ADR 0005), but the S3 adapter boundary (P6/P7), Spot-node risk acceptance
  + gp3 PVC via EBS CSI (P5), and an order-write kill switch + request bounds (P5) are all
  recorded but not built yet.

## What I want next
Continue the single task marked IN PROGRESS in docs/PROGRESS.md. Work one item at a time,
record evidence before checking anything off, and never create AWS resources outside a
session opened via docs/runbooks/aws-session.md (`/aws-session-start`). If asked to approve
a phase gate, make that its own commit ("Phase N gate approved by owner; activate Phase
N+1") before starting the next phase's work. Before P5 specifically: re-read the four
pending decisions above, since P5 is where two of them (Spot/PVC, kill switch) must
actually be implemented, not just remembered.
```
