# Architecture decision records

One file per decision: `NNNN-short-title.md`. Decisions are **superseded, never silently
amended** — to change an accepted decision, write a new ADR that names the one it supersedes
and flip the old one's status to `Superseded by NNNN`.

## Index

| ADR | Title | Status | Date |
|---|---|---|---|
| [0001](0001-application-stack.md) | Keep the application stack small | Accepted | 2026-07-17 |
| [0002](0002-mvp-aws-service-deferrals.md) | Defer Route 53/ACM, RDS, S3 images, and Secrets Manager from the MVP | Accepted | 2026-07-17 |
| [0003](0003-repo-hosting-and-branch-discipline.md) | Public bedoux-tech repo; direct-to-main until CI/CD | Superseded by 0004 | 2026-07-17 |
| [0004](0004-start-private-flip-public-later.md) | Host at bedoux-tech, start private, flip public before P9 | Accepted | 2026-07-18 |
| [0005](0005-helm-migration-hook-job.md) | Database migrations run as a Helm post-install/pre-upgrade hook Job | Accepted | 2026-07-19 |

## Template

```markdown
# ADR NNNN: Title

- Status: Proposed | Accepted | Superseded by NNNN
- Date: YYYY-MM-DD

## Context

What situation forces a decision.

## Decision

What was decided, stated in full sentences.

## Consequences

What becomes easier, harder, or deferred because of this decision.
```
