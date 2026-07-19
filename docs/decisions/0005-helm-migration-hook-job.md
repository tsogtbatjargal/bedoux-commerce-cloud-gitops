# ADR 0005: Database migrations run as a Helm pre-install/pre-upgrade hook Job

- Status: Accepted
- Date: 2026-07-19

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

Migrations run as a Kubernetes `Job` installed via Helm's `pre-install,pre-upgrade` hook
annotations (`helm.sh/hook: pre-install,pre-upgrade`), not as a manual or CI-only step.
This keeps the chart independently deployable — `helm install`/`helm upgrade` alone
produces a working release.

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
`pre-rollback`/`post-rollback` hooks. A Job hooked to `pre-install,pre-upgrade` simply
never executes during a rollback, so there is no downgrade path to suppress. Rollback
reverts the release's Kubernetes objects (Deployments, Services, config) to a prior
revision; it does not and will not touch schema state.

Confirmed live, not just from documentation: built a scratch chart with a
`pre-install,pre-upgrade`-hooked Job, `helm install`'d it (hook ran, `hook-job-1`),
`helm upgrade`'d it (hook ran again, `hook-job-2`), then `helm rollback`'d to revision 1
— only the Deployment's pods reverted; no `hook-job-3` was created and `kubectl get
events` showed no hook-related activity at all during the rollback. Torn down
afterward, no leftover namespace or resources.

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
