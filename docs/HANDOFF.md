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
- Phase 0 (bootstrap) complete: doc spine, git repo, ADRs 0001-0004, .claude config, slash
  commands, diagrams + SVG exports; all T-001..T-006 evidence in docs/PROGRESS.md.
- main is pushed to the PRIVATE repo bedoux-tech/bedoux-commerce-cloud (created from
  bedoux-vm's gh; local pushes as collaborator tsogtbatjargal over SSH).
- P0 gate approved by owner 2026-07-18 (gate commit in git log). Active phase: P1, next
  task P1.1 (install/pin toolchain).
- No AWS account activity yet. Region not pinned. aws CLI not installed; /aws-* commands
  must refuse. make and xmllint are also missing on this host — installing the toolchain
  is P1.1.

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
session opened via docs/runbooks/aws-session.md.
```
