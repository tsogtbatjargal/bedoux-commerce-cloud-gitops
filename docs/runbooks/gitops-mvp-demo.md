# GitOps local MVP — startup, verification, demo change, cleanup

Status: **local-only demo, reduced scope**, owner-approved 2026-09-09 (`docs/PROGRESS.md`
GO-MVP checklist entry). Not the full GO-1 design contract
(`docs/gitops-go1-design-contract.md`), which stays paused, unmodified, and deferred —
see `docs/DEFERRED-WORK.md` for everything this demo intentionally does not build or claim.
No AWS resource, no new remote repository, no router/Ingress, no automated recovery.

## What this demonstrates

One kind cluster, one dedicated namespace (`bedoux-demo`), Argo CD deploying the **existing**
`charts/bedoux` chart's api/web/Postgres from **this checkout's own git history** — a pinned
commit plus the current working tree's `charts/bedoux/` overlaid on top (see "Why a local
snapshot" below) — via a single (not multi-source) `Application`. Manual sync only
(`syncPolicy: {}`) — nothing here self-heals or auto-recovers. Browser access is via
`kubectl port-forward` only; no router is installed. One Git change, one manual sync, one
observed update. **Live-reproduced 2026-09-10 end to end**: `Synced`+`Healthy`, migration
completing before the api/web pods were created, `curl http://127.0.0.1:8000/health` returning
`{"status":"ok",...}` and `curl http://127.0.0.1:8080/` returning the real rendered page.

### Why a local snapshot, not a direct clone of the real GitHub remote

Building this demo found two real, permanent defects in `charts/bedoux`'s migration ordering
under Argo CD (not present under the legacy Helm CLI path) — see
`scripts/gitops-mvp-up.sh`'s header comment and `charts/bedoux/templates/migration-job.yaml`'s
header comment for the full live-reproduced detail. The fix is a small, backward-compatible,
opt-in chart change (`migration.gitopsMode`, default `false`; legacy Helm CLI behavior is
byte-for-byte unchanged — `python3 scripts/test_helm_render.py` still passes all 17 render
contracts). **This fix is committed and merged into `main`** (GO-MVP closeout, PR #91,
`feature/gitops-mvp` → `main`, merge commit `60e7d0757b1394f6d63a63530242eb7fed83eaf5` — an
earlier draft of this runbook described it as an uncommitted working-tree edit; that was
corrected once GO-MVP's PR actually merged it). A real `git clone` of the GitHub remote at or
after that merge already has this fix — it is no longer a prerequisite gap.
`gitops-mvp-up.sh` nonetheless still builds a **local-only git snapshot** on every run (this
checkout's `--app-revision` plus the current `charts/bedoux/` working tree, committed only to a
throwaway branch inside the snapshot itself, never in this repository's own working tree, and
never pushed anywhere) and serves it to the in-cluster Argo CD via a `hostPath` mount on the kind
node, referenced by its in-node path — the real GitHub remote is never contacted by this demo.
This is a deliberate, independent design choice (fast local iteration on uncommitted
`apps/api`/`apps/web`/`charts/bedoux` edits without needing to commit or push anything to the real
remote for every demo run), not a workaround for the now-merged chart fix.

## What this deliberately does NOT do

See `docs/DEFERRED-WORK.md` DEF-001 through DEF-011 for the full list and why. In short: no
durable attempt claim, no paired-Rollout coordinator/lease, no multi-source root/child
Application, no second environment, no env-repo PR automation, no AWS/EKS. Deployment-time
signature enforcement (`policy-controller`) is **not installed** — this is a local-demo
limitation, not a claimed security control. CI's existing Cosign signing/verification
(`.github/workflows/deploy-learning.yml`) is unaffected and unrelated to this demo.

## Prerequisites

`kind`, `kubectl`, `helm`, `podman`, `git`, `openssl` on `PATH`. Podman rootless,
`KIND_EXPERIMENTAL_PROVIDER=podman` (all three scripts set this). If cluster/image load fails
with a cgroup-controller error, see `docs/local-tooling.md`'s delegated-scope section
(`systemd-run --user --scope --slice=app.slice -p Delegate=yes ...`) — the scripts already wrap
the relevant commands this way, matching the pattern verified there.

**`fs.inotify.max_user_instances` headroom, live-reproduced 2026-09-10 as a real blocker, not a
hypothetical one.** kind, containerd, and each Argo CD pod (repo-server especially, which starts
a GPG-directory filesystem watcher) each consume inotify instances; this host's default
(`128`, shared across every other process the same user runs — desktop apps included) can be
exhausted, and `argocd-repo-server` then `CrashLoopBackOff`s with `"couldn't initialize inotify:
too many open files"` (`kubectl -n argocd logs -l app.kubernetes.io/name=argocd-repo-server`
shows this directly). This is NOT fixed by retrying or by `gitops-mvp-up.sh`'s own built-in
recovery (which only handles the separate old/new-ReplicaSet race during the repo-server's one
rollout, not genuine host-wide exhaustion) — `sudo` is required, and this script deliberately
never invokes it on your behalf. Before a fresh `gitops-mvp-up.sh` run, check
`cat /proc/sys/fs/inotify/max_user_instances` and, if genuinely tight, run:

```bash
sudo sysctl -w fs.inotify.max_user_instances=1024   # transient, until reboot or explicit restore
```

Restore it afterward (matches `docs/local-tooling.md`'s existing transient-sysctl precedent —
"any owner-approved transient increase must be restored after the drill; do not persist a sysctl
change silently"):

```bash
sudo sysctl -w fs.inotify.max_user_instances=128
```

## Startup

```bash
scripts/gitops-mvp-up.sh
```

Creates (or reuses) a kind cluster named `bedoux-gitops-mvp` (distinct from any existing local
dev cluster), builds the local snapshot described above, builds
`localhost/bedoux-api`/`localhost/bedoux-web` images from that snapshot's own tree (`git
archive`, not the live working tree directly — so the images genuinely match a fixed, recorded
commit, not whatever is currently on disk at build time), loads them into the node, installs
Argo CD (pinned `v3.5.2`, the same version researched in the full design contract's Gate 3),
patches `argocd-cm` so Ingress health is inert (no controller is installed in this MVP, so Argo's
default "wait for a LoadBalancer address" Ingress health check would otherwise block the
Application forever), mounts the local snapshot into `argocd-repo-server`, creates the
`bedoux-demo` namespace, and applies a single `Application` with `targetRevision` pinned to the
snapshot's exact commit SHA, `migration.gitopsMode: true`, and `syncPolicy: {}` (manual only). It
does **not** sync automatically — that is the next step.

If `argocd-repo-server`'s rollout doesn't complete within 90s, the script automatically checks
for a live-reproduced host-resource pattern (an old and a new repo-server pod both trying to run
at once exhausting this host's inotify instance budget) and attempts a bounded, logged recovery.
If that recovery itself fails, see "Prerequisites" above — `sudo` may be required, and this
script never invokes it for you.

## Verification

```bash
scripts/gitops-mvp-verify.sh
```

Run `scripts/gitops-mvp-verify.sh --help` for the authoritative, current flag/behavior contract —
this section summarizes it, but the script's own `--help` is what to trust if they ever drift.

By default (no `--skip-sync`), triggers exactly one manual sync
(`kubectl ... patch application bedoux-demo ... operation.sync`) and only reports success once
real, current-release cluster state confirms it:

- The Application reaches `Synced`+`Healthy` for the exact requested revision, or is tolerated
  `OutOfSync`/`Degraded` ONLY when every explanation is a positively-identified, terminal (Complete
  or Failed, from the Job's own `status.conditions`, never a succeeded/failed count that could
  reflect a still-retrying Job), retained PRIOR-release migration Job — this MVP deliberately never
  prunes old per-tag Jobs, so a real image-tag update permanently leaves them as "extra" resources
  even once the CURRENT release is genuinely healthy. Any other drift, or an unhealthy
  current-release resource, still fails — retained-Job tolerance is never used to excuse a real
  problem.
- For each of `api`/`web`, a pod-template-hash sample taken before the trigger is compared to the
  one active after it: a genuine match proves that workload was left UNCHANGED by this release (not
  applicable to it, not a violation); a genuine change is then checked for ordering across EVERY
  current-rollout replica — migration must have completed at/before all of them.
- Migration-before-workload ordering is reported from real object timestamps for **this run**,
  never assumed from the chart's hook annotation alone (Argo CD's Helm-hook-to-Argo-hook
  translation for `post-install,pre-upgrade` is not guaranteed to behave identically to a plain
  `helm install`; see "Known limitations" below).

**`--skip-sync` is explicitly status-only.** It never triggers a sync, so there is no genuine
before/after sample to compare — it never claims a workload is unchanged, never evaluates
ordering as a pass/fail, and always reports per-workload migration-ordering status as
`UNVERIFIED (--skip-sync)`. Its final summary line is tagged `STATUS ONLY` and is never a full
release-acceptance claim; it only confirms the Application's current sync/health/revision status
and the current migration Job's own terminal condition. Use it to peek at current state without
triggering a new sync — not as proof an update behaved correctly.

Then, unless `--no-port-forward` is passed, starts `kubectl port-forward` for `web`
(`http://127.0.0.1:8080/`) and `api` (`http://127.0.0.1:8000/health`) and curls both once, plus
the DB-backed `/products` endpoint. Press Ctrl-C to stop the port-forwards.

## Demo: one Git change, one sync, one visible update

**Live-reproduced end to end on the same cluster, 2026-09-10** — initial deploy at local
snapshot revision `153a1526adcbc7e30ad72f504bf5270702c116fe`, then this exact procedure produced
snapshot revision `c16d9e0a8c98e40d732b55db628bfe9e386346b6` and a real `web` `1/1`→`2/2` scale-up,
Postgres credential and data retained throughout, `/products` (DB-backed) returning `200` both
before and after — see `docs/PROGRESS.md`'s 2026-09-10 session log entry for the full transcript.

1. Make a small, visibly-observable change in the working tree — bumping `web.replicas` in
   `charts/bedoux/values.yaml` is the exact change proven above (no longer masked:
   `gitops-mvp-up.sh` does not override `replicas` in the Application, so the chart's own default
   governs). No commit or push is required for a `charts/bedoux` change: `gitops-mvp-up.sh`
   always overlays the CURRENT `charts/bedoux/` working tree into a fresh local snapshot commit
   on each run (see "Why a local snapshot" above). For an `apps/api`/`apps/web` source change
   instead, commit it locally first (`git commit`, still never pushed) so `--app-revision` can
   pin it and the image build picks it up.
2. Re-run `scripts/gitops-mvp-up.sh` on the SAME cluster (no `--keep-cluster` needed — it is
   never torn down between steps; add `--app-revision <sha>` if you committed an `apps/` change)
   — this rebuilds the images, builds a NEW local snapshot commit, reuses the existing Postgres
   credential (retained data — never regenerated), and re-points the Application's
   `targetRevision` at the new snapshot (still manual sync only; nothing deploys yet).
3. Run `scripts/gitops-mvp-verify.sh` — this triggers the sync and only reports success once the
   CURRENT release's migration Job, both workloads' rollouts, ordering, and HTTP/DB checks all
   pass (see "What this demonstrates" and DEF-013's fix above).
4. Observe the change: `kubectl --context kind-bedoux-gitops-mvp -n bedoux-demo get deploy web`
   showing the new replica count, and independently via
   `kubectl --context kind-bedoux-gitops-mvp -n argocd get application bedoux-demo
   -o jsonpath='{.status.sync.revision}'` reporting the new snapshot SHA.

## GO-MVP-U1: real A→B version update, migration ordering, and failure/recovery

Status: **owner-approved bounded post-MVP milestone, 2026-09-10** (`docs/PROGRESS.md` GO-MVP-U1
checklist). Builds on the GO-MVP demo above with a genuine application-version update (not a
scaling-only change) and a controlled migration failure. Same one-cluster boundary; still no AWS,
no second cluster, no automatic reconciliation.

**Live-reproduced end to end, 2026-09-10**, on `feature/gitops-version-update`:

1. **Source revision → image identity.** Revision A = `7595dfa236698001d1a195d3ef3ac20cc686b2cc`
   (image tag `mvp-7595dfa23669`) — pre-change baseline. Revision B =
   `92fc1e19fbc6dcddcdf2e973c728465f1663c598` (image tag `mvp-92fc1e19fbc6`) — API version
   `0.1.0`→`0.2.0` surfaced in `GET /health`'s new `"version"` field, a web footer ("Bedoux
   Commerce — build 0.2", confirmed present in the served JS bundle — this is a client-rendered
   SPA, so `curl /` alone never shows it, only the built bundle does), and a new backward-
   compatible Alembic migration (`9f1a2b3c4d5e`, adds nullable `orders.note`).
2. **Initial deploy + synthetic order.** `scripts/gitops-mvp-up.sh --app-revision
   7595dfa236698001d1a195d3ef3ac20cc686b2cc` then `scripts/gitops-mvp-verify.sh
   --no-port-forward`: `Synced`+`Healthy`, migration Job `bedoux-migrate-gitops-mvp-7595dfa23669`
   Succeeded before either pod was created. A synthetic product was inserted directly via `kubectl
   exec ... psql` (no product-write endpoint exists), then a real order was placed through the
   actual API: `POST /orders` → order `ae521e22-1154-4a7b-a3b9-331a47d5ec34`, `total_cents=3000`,
   `created_at=2026-09-10T20:31:09.313615Z`. Confirmed absent at this point: no `version` field in
   `/health`, no footer text in the JS bundle.
3. **Update to B on the SAME cluster/database.** `scripts/gitops-mvp-up.sh --app-revision
   92fc1e19fbc6...` (Postgres credential reused, not regenerated — same data) then
   `scripts/gitops-mvp-verify.sh --no-port-forward`. Confirmed the RUNNING image actually changed
   (`kubectl get pods -o jsonpath='{.spec.containers[0].image}'` → `localhost/bedoux-
   api:mvp-92fc1e19fbc6` / `localhost/bedoux-web:mvp-92fc1e19fbc6`, not a reused/stale tag),
   `GET /health` now reports `"version":"0.2.0"`, the served JS bundle now contains "build 0.2",
   migration Job `bedoux-migrate-gitops-mvp-92fc1e19fbc6` Succeeded at `2026-09-10T20:32:00Z`
   before either pod's creation, and `GET /orders/ae521e22-...` returned the ORIGINAL order
   unchanged — proving the database, not just the schema, survived the update.
   - **Live finding, fixed in this milestone:** because old per-tag migration Jobs are
     deliberately retained (never pruned), a real image update leaves the Application's aggregate
     `status.sync.status` permanently `OutOfSync` (the prior release's Job is an unpruned extra
     resource) even once the CURRENT release is genuinely healthy. `gitops-mvp-verify.sh` now
     tolerates `OutOfSync` ONLY when every non-`Synced` tracked resource is a `Job` that is not the
     current release's own migration Job — any other drift still fails. Without this fix, no real
     update could ever pass verification, only the scaling-only case GO-MVP originally proved.
4. **Migration ordering, on a throwaway branch — a controlled failure.** A deliberately broken
   migration (`de1e7e0000fa`, references a nonexistent table — guaranteed to fail) was added ONLY
   on a throwaway `demo-broken-migration` branch off B, never merged into
   `feature/gitops-version-update` or any reviewed release lineage. Revision C =
   `e444cf9b9da11601957bcb548f66867f1c41e045` (image tag `mvp-e444cf9b9da1`).
   `scripts/gitops-mvp-up.sh --app-revision e444cf9...` then `scripts/gitops-mvp-verify.sh
   --no-port-forward` **REFUSED** (non-zero exit) after the migration Job
   `bedoux-migrate-gitops-mvp-e444cf9b9da1` failed 3 pod attempts and reached `Failed`. Confirmed
   live: the api/web Deployments never advanced past B's images (Argo's sync-wave ordering gates
   wave 1 on wave 0's Job health, so the broken candidate never reached the workloads at all), and
   `GET /health` / `GET /orders/ae521e22-...` through the still-running B release both kept working
   throughout — the previously-working release and its order were never disturbed by the failed
   attempt. Alembic runs each migration in its own transaction, so the failed `ALTER TABLE`'s DDL
   was never committed (the pod's `Error` exit confirms the process exited before commit); this was
   not independently re-verified with a direct `psql` schema query before teardown.
   - **Second live finding, fixed in this milestone:** the retained FAILED Job from the aborted C
     attempt also permanently degraded the Application's aggregate `status.health.status` to
     `Degraded`, even after recovering back to B. `gitops-mvp-verify.sh` now tolerates `Degraded`
     under the identical "only a retained, non-current Job" condition as the `OutOfSync` tolerance
     above — never for a genuinely unhealthy current-release resource.
5. **Recovery — explicit, reviewed, manual.** `scripts/gitops-mvp-up.sh --app-revision
   92fc1e19fbc6...` (re-selecting B, no `alembic downgrade` ever invoked — recovery never
   automatically downgrades the schema) then `scripts/gitops-mvp-verify.sh --no-port-forward`
   PASSED again: migration Job `bedoux-migrate-gitops-mvp-92fc1e19fbc6` (still `Succeeded` from
   step 3), both rollouts complete, ordering intact. `GET /health` and `GET
   /orders/ae521e22-...` confirmed the release and the original order both fully usable again.
6. **Cleanup.** `scripts/gitops-mvp-down.sh` deleted the Application/namespace/cluster and the
   LAST-recorded release's images (B, per its documented exact-tag-only design — see "Scoped
   cleanup" below); revision A's and the throwaway revision C's images were removed manually
   afterward (`podman rmi`) since `gitops-mvp-down.sh` only ever knows the one tag read from the
   live Application, by design (no broader sweep). Confirmed clean: `kind get clusters` empty,
   no `bedoux-*` podman images remain. The `demo-broken-migration` branch and its worktree were
   left in place (not deleted) so its DO-NOT-MERGE fixture stays inspectable but is never part of
   `feature/gitops-version-update`'s history or this PR's diff.

See `docs/PROGRESS.md`'s GO-MVP-U1 session log entries for the full command transcript and every
observed timestamp/ID.

## Scoped cleanup

```bash
scripts/gitops-mvp-down.sh
```

Deletes only what this demo created: the `bedoux-demo` Application (its own
`resources-finalizer.argocd.argoproj.io` finalizer cascades deletion of its managed resources),
the `bedoux-demo` namespace (a backstop), the `bedoux-gitops-mvp` kind cluster (unless
`--keep-cluster`), and the exact-tagged `localhost/bedoux-api`/`localhost/bedoux-web` images read
live from the Application before deleting it. Refuses to touch a same-named cluster missing the
`kube-system/bedoux-gitops-mvp-owner` marker `gitops-mvp-up.sh` sets, and refuses outright (rather
than guessing) if the `kind`/`podman` inventory query itself fails. Run with `--dry-run` first to
preview exactly what would be deleted. Idempotent: running it again against an already-clean
state exits 0. Never touches another kind cluster, namespace, or image. Matches `AGENTS.md`'s
same-day-teardown default.

## Known limitations (recorded honestly, not glossed over)

- **Migration-before-workload ordering is structurally enforced, but by an MVP-scoped fix, not
  the full design contract's mechanism.** The chart's original `helm.sh/hook:
  post-install,pre-upgrade` (ADR 0005) does NOT gate ordering under Argo CD — live-reproduced:
  Argo's Helm-hook-to-Argo-hook translation runs it as a PreSync hook unconditionally (Argo has
  no install-vs-upgrade distinction), before the chart's own ServiceAccount/Postgres exist, so
  the migration Job failed with `serviceaccount bedoux-api not found`. Fixed with a small,
  opt-in `migration.gitopsMode` flag (default `false`, legacy Helm CLI path byte-for-byte
  unchanged) that switches to plain Argo sync-wave ordering (`-1`: ServiceAccount/Postgres;
  `0`: migration Job, gated by Argo's built-in Job health check; `1`: api/web, plus the Ingress
  objects so their perpetual "no controller" health never blocks anything). This is the same
  wave design the full GO-1 design contract's Gate 2 already specified
  (`docs/gitops-fixtures/gitops-migration-job.example.yaml`) — reused here because it was already
  designed and uncontested, not because this MVP reopened Gate 2. `gitops-mvp-verify.sh` still
  reports the actual observed ordering from real timestamps every run rather than asserting it.
- **No registry, so "pinned images" means a deterministic local build tag + local podman image
  ID, not a registry digest.** This is weaker provenance than the full design contract's
  digest-based binding (Gate 1, deferred) — acceptable for a local demo with synthetic data, not
  claimed as production-equivalent.
- **The Application's source is a local-only git snapshot, not the real GitHub remote**, until
  the `charts/bedoux` migration-ordering fix above is pushed and reviewed — see "Why a local
  snapshot" above. Re-run with a real upstream commit once that fix lands; no script change
  needed, the `file://`-style local-path source pattern also works with a real clone URL.
- **No admission/signature enforcement is installed.** Anything can run in this namespace.
  Acceptable only because the namespace holds synthetic demo data and is torn down same-session.
- **No automated recovery of any kind.** A failed sync, a failed migration, or a crashed pod is
  left as-is for manual operator inspection — by design (`syncPolicy: {}`, no self-heal).
- **This host's `fs.inotify.max_user_instances` can be exhausted by kind + Argo CD + everything
  else already running as this user.** See "Prerequisites" above; requires a `sudo`-run, owner-
  restored transient sysctl bump on a tight host, matching `docs/local-tooling.md`'s existing
  precedent for this exact class of local constraint.
- **Concurrency/shared-image limitations remain deferred (DEF-015).** GO-MVP-U1 closed the
  startup inventory-error branch and the real-update/migration-ordering/failure-recovery proof
  above, all still within a single demo cluster at a time. Multiple concurrent demo clusters
  sharing base-SHA image tags, and broader new-image/schema shapes beyond what was actually
  demonstrated here, are still out of scope — see `docs/DEFERRED-WORK.md` DEF-015 for the
  retained subfinding and revisit criteria.
