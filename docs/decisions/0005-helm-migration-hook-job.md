# ADR 0005: Database migrations run as a Helm post-install/pre-upgrade hook Job

- Status: Accepted
- Date: 2026-07-19 (hook trigger corrected same-day during P3.4 — see note below)

## Context

P3.4 converts the plain `k8s/` manifests into a Helm chart. Right now migrations and
seed data are run manually via `kubectl exec deploy/api -- python -m alembic upgrade
head` after every apply (P3.1–P3.3 all did this by hand). That doesn't survive into a
Helm-managed release: `helm install`/`helm upgrade` must be able to stand up a working
release on its own, without an operator remembering a manual follow-up step — otherwise
Helm isn't actually the deployment mechanism, it's just a templating convenience wrapped
around a manual runbook.

The question is where migrations run (a Helm hook Job vs. a manual/CI step) and what
happens to them across `helm rollback`, since rollback is one of P3.5's required drills
and a botched automatic downgrade could destroy data.

## Decision

Migrations run as a Kubernetes `Job` installed via Helm's `post-install,pre-upgrade`
hook annotations (`helm.sh/hook: post-install,pre-upgrade`), not as a manual or CI-only
step. This keeps the chart independently deployable — `helm install`/`helm upgrade`
alone produces a working release.

> **Correction, same day, during P3.4 chart-building:** this ADR originally specified
> `pre-install,pre-upgrade`. Building the actual chart caught a real bug in that choice
> before it ever ran against a live release: a `pre-install` hook fires **before** any
> of the chart's own non-hook resources exist — verified live with a second scratch
> chart (a Secret templated as a normal resource, a `pre-install`-hooked Job reading it
> via `secretKeyRef`; `helm install` failed with `DeadlineExceeded`, no pod ever
> scheduled, because the Secret didn't exist yet when the hook tried to run). This
> chart's migration Job depends on exactly that kind of Secret
> (`postgres-credentials`), so it would have failed the same way on every fresh
> install. Switching to `post-install` (confirmed via the same scratch-chart method:
> fires after install-time resources exist, still fires before an existing release's
> resources are upgraded via `pre-upgrade`, and still never fires on rollback) fixes it
> without changing any of the decision's actual intent — fail-fast, no auto-downgrade,
> opt-in seed all stand as originally decided. Corrected in place rather than
> superseded, since this is a same-day factual fix to an implementation detail caught
> before any chart depended on the wrong version, not a reconsidered tradeoff (same
> discipline as the P2.3 Numeric→Integer migration fix in `docs/PROGRESS.md`).

The Job:

- runs `alembic upgrade head` and nothing else;
- fails the release if the migration fails (Helm hook Jobs block the release on
  non-zero exit by default — no extra config needed for this part);
- sets `backoffLimit` and `activeDeadlineSeconds` so a stuck or endlessly-retrying
  migration fails the release promptly instead of hanging it;
- is kept around after success, not deleted — `helm.sh/hook-delete-policy` is set to
  `before-hook-creation` only (delete the *previous* Job right before the *next* one
  runs), never `hook-succeeded`. The completed Job stays inspectable until the next
  release.

**No automatic `alembic downgrade` runs on `helm rollback`, and none is added.** This
isn't a safety feature bolted on top — it's already the default behavior. Verified
directly (not assumed) against Helm's hook model: `helm rollback` only fires
`pre-rollback`/`post-rollback` hooks. A Job hooked to `post-install,pre-upgrade` simply
never executes during a rollback, so there is no downgrade path to suppress. Rollback
reverts the release's Kubernetes objects (Deployments, Services, config) to a prior
revision; it does not and will not touch schema state.

Confirmed live, not just from documentation, in two rounds: first with a scratch chart
using `pre-install,pre-upgrade` (`helm install` → hook ran as `hook-job-1`, `helm
upgrade` → hook ran again as `hook-job-2`, `helm rollback` to revision 1 → no
`hook-job-3` created, no hook-related events at all) — this proved the rollback claim
but the trigger was later found to be wrong for a fresh install (see the correction
note above). Re-run against a second scratch chart using the corrected
`post-install,pre-upgrade`: fresh `helm install` succeeded (hook correctly saw its
dependency Secret already created), `helm upgrade` fired the hook again exactly once,
and `helm rollback` again produced zero new hook Jobs. Then confirmed a third time
against this project's actual `charts/bedoux` chart and live kind cluster during P3.4
(see `docs/PROGRESS.md`'s P3.4 evidence): real install, real upgrade, a deliberately
broken upgrade that failed safely without touching the running app, recovery, and a
real `helm rollback` with all data intact. All scratch resources torn down after each
round, no leftover namespaces.

Because rollback never runs a downgrade, every migration must be written to be
**backward-compatible (expand/contract style)** once the schema has more than one
migration: a migration must work correctly with both the old and new application code
running against it simultaneously, since a rollback can leave newer schema state paired
with older application code mid-drill. Purely additive changes (new nullable column, new
table) are safe by default; anything that removes or renames a column needs an
expand-then-contract split across two releases.

Seed data (`python -m app.seed`) is **not** part of this hook and does not run on every
upgrade. It becomes a separate Job, gated behind an explicit chart value (e.g.
`seed.enabled`), off by default, intended only for the learning profile bootstrapping a
fresh environment — never wired into the standard install/upgrade path where it could
silently re-run against a database that already has real order data.

## Consequences

- `helm install`/`helm upgrade` alone produce a schema-correct release — no manual
  `kubectl exec` step required, and no CI-only migration path to keep in sync with the
  chart separately.
- A failed migration fails the whole release (`helm upgrade` returns non-zero, the
  release does not proceed) rather than silently deploying app code against a stale
  schema.
- `helm rollback` is schema-inert by construction, which is exactly the property P3.5's
  rollback drill needs to demonstrate safely — no risk of an accidental downgrade
  destroying data during that drill.
- Once there is more than one migration, every new migration needs deliberate
  backward-compatibility review — this is real ongoing discipline, not a one-time setup
  cost, and should be called out explicitly whenever P3.5's rollback drill or any future
  schema change happens.
- Seed stays intentionally separate and manual-opt-in; production/AWS profiles never
  wire `seed.enabled` on by default.
