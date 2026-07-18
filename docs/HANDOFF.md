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

## Current state (as of 2026-07-17)
- Phase 0 (bootstrap) nearly complete: doc spine, git repo, ADRs 0001-0003, .claude config,
  and slash commands exist. Remaining: P0.5 diagram SVG exports verified via `make docs-check`,
  P0.6 GitHub push to bedoux-tech/bedoux-commerce-cloud (owner confirms visibility first).
- No AWS account activity yet. AWS region not pinned. /aws-* commands must refuse.

## Locked decisions (do not revisit without a new ADR in docs/decisions/)
- ADR 0001: small stack — React/Vite/TS, FastAPI, PostgreSQL, image-storage adapter boundary.
- ADR 0002: MVP defers Route53/ACM (use ALB DNS, HTTP), RDS (in-cluster Postgres until P7),
  S3 images and Secrets Manager (P7). No NAT Gateway in the learning profile.
- ADR 0003: GitHub bedoux-tech/bedoux-commerce-cloud, public; direct-to-main until P6;
  commit convention `<TaskID> complete: ...` and gate commits.

## What I want next
Continue the single task marked IN PROGRESS in docs/PROGRESS.md. Work one item at a time,
record evidence before checking anything off, and never create AWS resources outside a
session opened via docs/runbooks/aws-session.md.
```
