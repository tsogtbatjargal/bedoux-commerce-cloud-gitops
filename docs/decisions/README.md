# Architecture decision records

One file per decision: `NNNN-short-title.md`. Decisions are **superseded, never silently
amended** — to change an accepted decision, write a new ADR that names the one it supersedes
and flip the old one's status to `Superseded by NNNN`.

## Index

| ADR | Title | Status | Date |
|---|---|---|---|
| [0001](0001-application-stack.md) | Keep the application stack small | Accepted | 2026-07-17 |
| [0002](0002-mvp-aws-service-deferrals.md) | Defer Route 53/ACM, RDS, S3 images, and Secrets Manager from the MVP | Accepted | 2026-07-17 |
| [0003](0003-repo-hosting-and-branch-discipline.md) | Public bedoux-tech repo; direct-to-main until CI/CD | Accepted | 2026-07-17 |

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
