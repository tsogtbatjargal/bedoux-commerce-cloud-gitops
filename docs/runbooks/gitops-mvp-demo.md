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
contracts). That fix is, as of this writing, **an uncommitted, dirty working-tree edit in this
checkout** (`git status` shows it modified, not committed — an earlier draft of this runbook
wrongly said "committed in this working tree"; corrected per Codex's
2026-09-09T20:27:22-06:00 review) — it is not pushed to the real GitHub remote, and
`gitops-mvp-up.sh` does not commit or push it on your behalf; that is a separate, explicit
action. Until it happens, `gitops-mvp-up.sh` builds a **local-only git snapshot** (this
checkout's `--app-revision` plus the current `charts/bedoux/` working tree, committed only to a
throwaway branch inside the snapshot itself, never in this repository's own working tree, and
never pushed anywhere) and serves it to the in-cluster Argo CD via a `hostPath` mount on the kind
node, referenced by its in-node path — the real GitHub remote is never contacted by this demo.

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

Triggers exactly one manual sync (`kubectl ... patch application bedoux-demo ... operation.sync`),
waits for the Application to report `Synced`+`Healthy`, then reads real object timestamps to
report whether the migration Job actually completed before the first `api` pod was created for
**this run** — printed honestly either way, never assumed from the chart's hook annotation alone
(Argo CD's Helm-hook-to-Argo-hook translation for `post-install,pre-upgrade` is not guaranteed to
behave identically to a plain `helm install`; see "Known limitations" below). Then starts
`kubectl port-forward` for `web` (`http://127.0.0.1:8080/`) and `api`
(`http://127.0.0.1:8000/health`) and curls both once. Press Ctrl-C to stop the port-forwards.

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
