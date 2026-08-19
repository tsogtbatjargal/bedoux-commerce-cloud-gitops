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
| [0004](0004-start-private-flip-public-later.md) | Host at bedoux-tech, start private, flip public before P9 | "flip public" clause superseded by 0013 | 2026-07-18 |
| [0005](0005-helm-migration-hook-job.md) | Database migrations run as a Helm post-install/pre-upgrade hook Job | Accepted | 2026-07-19 |
| [0006](0006-spot-node-gp3-pvc.md) | Accept Spot-node interruption risk in P5; provision a real gp3 PVC via EBS CSI | Accepted | 2026-07-23 |
| [0007](0007-bedoux-iam-scoped-self-escalation-fix.md) | Close a self-escalation hole in bedoux-iam-scoped; add the EKS nodegroup SLR check | Superseded in part by 0015 | 2026-07-28 |
| [0008](0008-alb-no-rewrite-web-proxies-api.md) | ALB Ingress can't rewrite paths — web's own nginx proxies /api internally | Accepted | 2026-07-28 |
| [0009](0009-github-actions-oidc-least-privilege.md) | GitHub Actions uses a branch-bound OIDC role with namespace-scoped deployment access | Accepted | 2026-07-30 |
| [0010](0010-local-git-guardrail-for-private-repo.md) | Use a local pre-push guardrail while private-repository branch protection is unavailable | Accepted | 2026-07-30 |
| [0011](0011-s3-presigned-image-adapter.md) | Keep product-image delivery behind an API-side presigned-S3 adapter | Accepted | 2026-08-02 |
| [0012](0012-secrets-manager-direct-workload-retrieval.md) | Retrieve the database credential directly from Secrets Manager | Accepted | 2026-08-03 |
| [0013](0013-remain-private-at-p9.md) | Remain private at P9; ADR 0004's public flip is not exercised | Accepted | 2026-08-07 |
| [0014](0014-post-p9-optimization-track-scope.md) | Post-P9 optimization track (P10-P14): scope and guardrail interactions | Accepted | 2026-08-09 |
| [0015](0015-bound-delegated-project-roles.md) | Bound every delegated project role to the operator's non-IAM ceiling | Accepted | 2026-08-10 |
| [0016](0016-owner-applied-eks-passrole-v6.md) | Add exact EKS execution-role PassRole to the owner-managed policy | Accepted | 2026-08-17 |
| [0017](0017-az-pinned-nodegroups-soft-failover-spread.md) | Pin the P11 HA node groups by AZ and permit one-AZ failover | Superseded in part by 0018 | 2026-08-18 |
| [0018](0018-omit-mindomains-for-soft-topology-spread.md) | Omit minDomains from the soft AWS topology-spread profile | Accepted | 2026-08-18 |
| [0019](0019-bound-alb-draining-and-readiness-gates.md) | Bound ALB draining and require target-health readiness gates | Accepted | 2026-08-18 |

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
