# ADR 0027: Argo sync-wave migration Jobs supersede the Helm hook for the GitOps profile only

- Status: Proposed
- Date: 2026-09-09
- Scope: GO-1 design contract, Gate 2 (migration ordering). No implementation, installation
  or cluster mutation is authorized by this record.
- Supersedes: [ADR 0005](0005-helm-migration-hook-job.md), **in part** — GitOps-managed
  environments only. ADR 0005 remains Accepted and unchanged for the legacy Helm/P13 path.
- Related: [Proposed ADR 0026](0026-two-repository-argocd-delivery.md),
  [docs/gitops-go1-design-contract.md](../gitops-go1-design-contract.md).

## Context

ADR 0005 runs database migrations as a Kubernetes `Job` triggered by Helm's
`post-install,pre-upgrade` hook annotations, named `bedoux-migrate-{{ .Release.Revision }}`.
This depends on `helm upgrade`'s own lifecycle: Helm decides when the hook fires, tracks
`Release.Revision` itself, and (per ADR 0005) never fires the hook on rollback.

Argo CD renders this chart's templates via Helm's templating engine but does not run
`helm upgrade` — it does not honor `helm.sh/hook*` annotations as Helm does, and it has no
stable, Argo-visible equivalent of `Release.Revision` to key a Job name on. Pointing Argo at
the chart unchanged does not reproduce ADR 0005's guarantees; it silently drops them. This is
the same class of problem ADR 0005 itself caught for `pre-install` vs. `post-install` timing,
now recurring one layer up under a different orchestrator.

## Decision

For GitOps-managed environments only, replace the Helm-hook migration Job with a plain
(non-hook) `Job` resource ordered by an Argo `sync-wave` annotation, gated by Argo's built-in
resource health checks rather than Helm's hook lifecycle:

- **Wave -1**: database/Secret prerequisites (existing `postgres` StatefulSet/Service/Secret).
  Argo's built-in health assessment for these resource kinds must report Healthy before the
  next wave applies.
- **Wave 0**: the migration `Job`, named from the reviewed release record's `releaseId` field
  (`bedoux-migrate-{releaseId}`), never from `.Release.Revision`. Argo's built-in Job health
  check (`status.conditions[Complete]=True`) gates wave 1.
- **Wave 1**: the existing `api`/`web` Deployments, unchanged.

A terminally failed Job (`backoffLimit` exhausted) leaves the Application `Degraded` at wave 0
and is never recreated or retried by routine reconciliation, because its name is stable per
`releaseId` and only a new reviewed release record produces a new name and a new attempt. This
is a deliberate design property, not an incidental one: it is what keeps a rejected migration
from being silently retried on every sync or controller restart.

No automatic `alembic downgrade` is added anywhere in this path — the same non-feature ADR 0005
already establishes, preserved here by never invoking it, not by a togglable flag.

A worked, locally validated example of this Job (sync-wave annotation, `releaseId`-derived
name, bounded `backoffLimit`/`activeDeadlineSeconds`, no Helm hook annotations) is recorded at
`docs/gitops-fixtures/gitops-migration-job.example.yaml`. It is a **design fixture only** — not
wired into `charts/bedoux`, not applied to any cluster. Wiring it into the chart behind a
GitOps-profile flag, and proving the wave ordering against a live Argo install, is GO-3 work.

CI-run migration (executing the migration from the "Prepare release" GitHub Actions workflow,
before Argo ever sees the release) was considered and rejected: it would require giving
application CI live network access and credentials to the target environment's database,
which cuts directly against this track's broader goal of removing routine cluster/data-plane
credentials from CI once Argo owns deployment (`docs/gitops-expansion-plan.md`).

## Relationship to ADR 0005

| | ADR 0005 (unchanged) | This ADR (GitOps profile only) |
|---|---|---|
| Trigger | Helm `post-install,pre-upgrade` hook | Argo `sync-wave` + built-in health gate |
| Job identity | `.Release.Revision` | reviewed release record's `releaseId` |
| Applies to | Legacy Helm/P13 path (`scripts/p13-canary-rollout.sh`, all current AWS/kind profiles) | Future GitOps-managed dev/staging environments only (GO-3+) |
| Preserved contract | Forward-only, no automatic downgrade, fail-fast, opt-in seed, bounded `backoffLimit`/`activeDeadlineSeconds` | Same four properties, re-derived under Argo's execution model |

Both Jobs may exist in the same chart source simultaneously, gated by mutually exclusive
values (legacy `migration.enabled` hook vs. a new GitOps-profile flag) — GO-3 designs and
implements that gate; this ADR fixes the ordering/identity mechanism it must implement.

## Consequences

- The legacy path (P13 canary script, existing AWS/kind Helm profiles) is completely
  unaffected — ADR 0005 continues to govern it exactly as accepted.
- GitOps-managed environments gain a migration mechanism that behaves correctly under Argo's
  actual execution model instead of silently inheriting assumptions from a lifecycle Argo
  doesn't run.
- A stuck or terminally failed migration blocks that environment's promotion indefinitely
  until a reviewed fix-forward or revert PR merges a new `releaseId` — consistent with this
  track's "no automatic retry, reviewed recovery only" rule
  (`docs/runbooks/gitops-recovery.md`).
- GO-3 still has to do real implementation work: wire this Job template into the chart behind
  a GitOps-profile flag, generate/consume the release record, and prove the three-wave
  ordering and health gating against a live local Argo install. This ADR fixes the design; it
  does not claim that work is done.

## Acceptance boundary

This record stays Proposed until the owner explicitly accepts it as part of GO-1 closeout.
Acceptance does not authorize chart changes, installation or any cluster mutation — those
remain GO-2/GO-3 work under their own activation.
