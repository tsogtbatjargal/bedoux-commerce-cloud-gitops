# Handoff

Everything above the fenced block is reference; **paste the fenced block below into a new
Claude Code / Codex / agent session** to continue this project. Regenerate this file at every
session closeout (`/closeout`).

---

```text
You are continuing work on bedoux-commerce-cloud at
/var/home/tsogtb/git-projects/bedoux/bedoux-commerce-cloud — a long-running, agent-agnostic
AWS EKS commerce learning project with a hard USD 20/month budget.

## First actions
1. Read START-HERE.md, then AGENTS.md, then docs/PROGRESS.md (the only authoritative state).
2. Verify the last checkpoint before changing anything.

## Current state (as of 2026-07-18)
- Phase 0 (bootstrap) complete and gate approved: doc spine, git repo, ADRs 0001-0004,
  .claude config, slash commands, diagrams + SVG exports; all T-001..T-006 evidence in
  docs/PROGRESS.md. main is pushed to the PRIVATE repo bedoux-tech/bedoux-commerce-cloud
  (local pushes as collaborator tsogtbatjargal over SSH).
- Phase 1 (local toolchain) complete: aws/kubectl/eksctl/kind/helm/terraform installed as
  static binaries at host ~/.local/bin; make lives in the bedoux-aws toolbox with a
  ~/.local/bin/make wrapper (must call /usr/bin/make by absolute path inside the toolbox
  — a bare `make` recurses, see docs/local-tooling.md). `make tools-check` and
  `make docs-check` both pass from a plain host shell. P1 gate pending owner approval.
- No AWS account activity yet; aws CLI installed but never configured/contacted.
  /aws-* commands must still refuse until credentials exist.
- Known gap for P3: `kind create cluster` against rootless Podman needs a systemd
  cgroup `Delegate=yes` drop-in — not yet fixed, must be step one of P3.1.

## Locked decisions (do not revisit without a new ADR in docs/decisions/)
- ADR 0001: small stack — React/Vite/TS, FastAPI, PostgreSQL, image-storage adapter boundary.
- ADR 0002: MVP defers Route53/ACM (use ALB DNS, HTTP), RDS (in-cluster Postgres until P7),
  S3 images and Secrets Manager (P7). No NAT Gateway in the learning profile.
- ADR 0004 (supersedes 0003): private repo at bedoux-tech, flip public before P9 after a
  full-history secrets sweep; direct-to-main until P6; commit convention
  `<TaskID> complete: ...` and gate commits.

## What I want next
Continue the single task marked IN PROGRESS in docs/PROGRESS.md. Work one item at a time,
record evidence before checking anything off, and never create AWS resources outside a
session opened via docs/runbooks/aws-session.md. If asked to approve the P1 gate, make that
its own commit ("Phase 1 gate approved by owner; activate Phase 2") before starting P2 work.
```
