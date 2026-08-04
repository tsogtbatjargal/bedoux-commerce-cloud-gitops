# Progress

This file is the **only authoritative execution state** for bedoux-commerce-cloud.
Do not infer progress from files existing. A task is complete only when its checkbox is
checked here and its evidence is recorded in the session log.

## Overall status

| Field | Value |
|---|---|
| State | IN PROGRESS |
| Active phase | P8 — Observability and operations drills |
| Active task | P8.1 — app logging + request IDs (NOT STARTED). |
| Last verified | 2026-08-04T12:21:51-06:00 — owner approved the P7 gate; P8 activated by dedicated gate commit. |
| AWS resources currently live | No temporary AWS resources. Persistent allowlist only: encrypted state bucket, two ECR repositories, cluster/node/GitHub deployment roles and policies, ALB-controller role/policy, GitHub OIDC provider, and their persistent IAM attachments. |
| Month-to-date estimated AWS spend | Owner confirmed actual and forecast below USD 16 before the 2026-08-01 P7.1 session; billing data lags. Recheck the console before any new session rather than treating the prior value as current. |
| Next operator action | Begin P8.1 locally; no temporary AWS session is open. |

Allowed states: `NOT STARTED` / `IN PROGRESS` / `BLOCKED` / `COMPLETE`.

## Known facts

- AWS region: **`ca-central-1`** (pinned 2026-07-19, owner choice — closer to
  America/Edmonton than the more commonly-tutorialed `us-east-1`; P4.3).
- AWS account: **new paid-plan account created by owner 2026-07-19** (Proton Mail
  signup). Root used only once, briefly, to enable root MFA and bootstrap a non-root
  identity — never used for routine work (account ID intentionally never recorded
  here). **Working identity is IAM user `bedoux-admin`**, in group `bedoux-admins`
  with `PowerUserAccess` (AWS managed; excludes IAM/Organizations) plus a small custom
  policy `bedoux-iam-scoped` (**v3** as of 2026-07-28, see ADR 0007) granting IAM
  role/policy/OIDC-provider actions only on `bedoux-*`-named resources (the minimum
  `eksctl`/IRSA need), **plus an explicit `Deny` on `bedoux-admin` ever modifying
  `bedoux-iam-scoped` itself** (closes a self-escalation path found and fixed during
  P5.1 — full detail in `docs/decisions/0007-bedoux-iam-scoped-self-escalation-fix.md`).
  MFA (passkey) enabled on
  `bedoux-admin`. CLI access via a named profile, **`--profile bedoux-admin`** —
  `aws sts get-caller-identity --profile bedoux-admin` confirmed
  `arn:aws:iam::<redacted>:user/bedoux-admin`, not root. Every future AWS command in
  this project (CLI, `eksctl`, Terraform, `/aws-*` slash commands) uses this profile;
  root stays reserved for account-level console actions only. Full detail in
  `docs/local-tooling.md`'s "AWS CLI identity" section.
- **Every IAM role/policy this project creates from here on must be named `bedoux-*`**
  — the scoped IAM policy above only grants role/policy management on that naming
  pattern.
- **Declined AWS's "Agent Toolkit for AWS" auto-setup script** (offered during account
  signup) — it would have reinstalled the AWS CLI over our pinned version, auto-edited
  `CLAUDE.md`/`AGENTS.md`, and added an AWS MCP server + skills with unreviewed scope.
  Took only the useful part (the `aws login` SSO auth pattern) and ran it manually
  instead. If revisited later, review the MCP server's exact tool/permission list
  before adding it.
- GitHub: `bedoux-tech/bedoux-commerce-cloud`, **private** until a pre-P9 history sweep
  (ADR 0004); `tsogtbatjargal` pushes over SSH from the workstation; the `bedoux-tech` gh
  auth lives on bedoux-vm (openclaw user).
- Standard tags for every AWS resource: `project=bedoux-commerce-cloud`, `environment=learning`.
- **Project optimization target, owner-confirmed 2026-07-19: this is an
  EKS/platform-engineering portfolio.** The commerce app is already credible enough as a
  vehicle — operational evidence (drills, rollback, IAM, failure handling) outranks
  additional product features whenever the two compete for time.

## Pending owner-approved decisions — do not miss these in their phase

Full detail in `docs/IMPLEMENTATION-PLAN.md`'s "Pending owner-approved decisions"
section (also flagged inline at each phase there). One-line index so a phase-start
check can't miss them:

- ~~**P3.4**~~ — **DONE 2026-07-19.** Helm chart built in `charts/bedoux/` per
  [ADR 0005](decisions/0005-helm-migration-hook-job.md) (`post-install,pre-upgrade`,
  corrected same-day from an initial `pre-install` design — see the ADR). Full
  install/upgrade/failure/rollback evidence in this file's P3.4 entry below.
- ~~**P6/P7 boundary**~~ — **DONE 2026-08-02.** [ADR 0011](decisions/0011-s3-presigned-image-adapter.md): API returns storage-neutral `image_url`; static mode returns
  `/static/products/...`; S3 mode returns an API-generated presigned URL using the pod's
  scoped IRSA identity; frontend remains storage-agnostic and FastAPI never proxies bytes.
- ~~**P5 — Spot/gp3**~~ — **DONE 2026-07-23.** [ADR 0006](decisions/0006-spot-node-gp3-pvc.md):
  Spot risk documented explicitly (no multi-node failover engineered); chart-side
  support for a real `gp3` StorageClass (`ebs.csi.aws.com`) landed in
  `charts/bedoux/templates/storageclass.yaml` + `values-aws.yaml`
  (`storageClass.create: true`, `postgres.storageClassName: gp3`). Full evidence in
  this file's P5-pre-work entry below; live proof against a real EBS CSI add-on is
  P5.1's job once the cluster exists.
- ~~**P5 — kill switch**~~ — **DONE 2026-07-23.** `BEDOUX_ORDERS_ENABLED` (off by
  default in `values-aws.yaml`, on by default everywhere else), 20-line order cap,
  the existing 100-qty-per-line cap, a 64KB request-body-size middleware, and a
  frontend "ordering disabled" state — all live-verified against the kind cluster
  (503 not a crash, `/health` reflects state, real browser shows the disabled banner
  and re-enables cleanly). ALB inbound CIDR restriction is deferred to P5.3 (needs a
  real ALB to attach a security group to). Full evidence in this file's P5-pre-work
  entry below.

## Known open issues (not blockers, revisit when fixable)

- **22 unfixed OS-level CVEs on the API image's `python:3.12-slim` (Debian 13) base**,
  found during the P2.5 trivy scan (2026-07-18). No upstream fix exists yet — this is
  not something the app can fix on its own. Re-scan with
  `trivy image --severity HIGH,CRITICAL --input /tmp/image.tar` (recipe in
  `docs/local-tooling.md`) periodically and whenever the base image tag is bumped;
  fix opportunistically the moment a patched Debian package lands upstream, otherwise
  revisit at the latest before P9 (interview package) so the final state is current.
- **ECR tagged-image lifecycle prefix mismatch (identified 2026-07-31):** the ECR rule matches
  `sha-` tags, while P6.4's deployment workflow emits bare commit-SHA tags. This is a bounded
  storage/cost-hygiene gap, not a runtime or security issue; defer the one-line alignment to a
  focused follow-up after the first controlled P6.4 session rather than delaying its evidence.

## Phase checklist

### P0 — Bootstrap

- [x] P0.1 COMPLETE — doc spine created (START-HERE, AGENTS, CLAUDE shim, PROGRESS,
      IMPLEMENTATION-PLAN merge, TEST-PLAN, HANDOFF); `project-plan.md` +
      `learning-roadmap.md` merged and removed. Evidence: session log 2026-07-17; T-001.
- [x] P0.2 COMPLETE — ADR index + 0002 (MVP deferrals) + 0003 (repo hosting) created;
      0001 flipped to Accepted. Evidence: `docs/decisions/README.md` status table.
- [x] P0.3 COMPLETE — README banner + doc index, architecture MVP-vs-production table,
      aws-session closeout section, Makefile docs-check extension. Evidence: T-001 run.
- [x] P0.4 COMPLETE — `.claude/settings.json` read-only allowlist + `/catchup`,
      `/aws-session-start`, `/aws-teardown-verify`, `/closeout` commands. Evidence: T-006.
- [x] P0.5 COMPLETE — diagrams revised (system-context deferral styling, learning-path
      → P0–P9) and exported to SVG via podman `rlespinasse/drawio-export`. Evidence:
      `make docs-check` OK 2026-07-18; visual self-check of PNG previews passed.
- [x] P0.6 COMPLETE — GitHub repo `bedoux-tech/bedoux-commerce-cloud` created **private**
      (ADR 0004) from bedoux-vm's gh, `tsogtbatjargal` added as push collaborator, `main`
      pushed from the workstation. Evidence: T-002 — `git remote -v` shows origin;
      push output `* [new branch] main -> main`; session log 2026-07-18.

**P0 gate approved by owner 2026-07-18** (evidence: T-001..T-006 above; gate commit in git log).

### P1 — Local tooling

- [x] P1.1 COMPLETE — aws/kubectl/eksctl/kind/helm/terraform installed as static binaries
      to host `~/.local/bin` (Silverblue-clean, no rpm-ostree layering); `make` (+ podman
      package for presence-check parity) installed via dnf in the pre-existing `bedoux-aws`
      toolbox; `~/.local/bin/make` wrapper makes `make <target>` work transparently from a
      host shell. Evidence: T-011 — `make tools-check` → "All project prerequisites are
      available." from a plain host shell; `make docs-check` → "docs-check OK".
- [x] P1.2 COMPLETE — pinned versions + install method recorded in
      `docs/local-tooling.md`, including the make-wrapper recursion pitfall and a known
      P3 gap (kind + rootless Podman needs cgroup `Delegate=yes`, not yet fixed).

**P1 gate approved by owner 2026-07-18** (owner said "keep going on P2"; evidence: T-011
above; gate commit in git log).

### P2 — Local application slice

- [x] P2.1 COMPLETE — `apps/api` FastAPI skeleton: `/health` endpoint, OpenAPI docs,
      pytest suite, multi-stage non-root Dockerfile (runs as uid 10001 `bedoux`).
      Evidence: T-102 `pytest` 2/2 passed; T-101-partial — `uvicorn` booted on
      127.0.0.1:8123, real `curl /health` → `{"status":"ok"}` (200), real `curl /docs` →
      200; T-103 `/openapi.json` title matches; T-104 `podman build` clean, container run
      verified non-root (`id` → uid=10001(bedoux)), real HTTP round-trip through the
      container's published port, image size 163MB, container removed after test — no
      leftover state.
- [x] P2.2 COMPLETE — SQLAlchemy models (`Product`, `Order`, `OrderItem`), Alembic
      migrations (autogenerated initial revision), idempotent seed script (6 synthetic
      products), root `docker-compose.yml` wiring `postgres` + `api` (frontend added in
      P2.5). Evidence: real `postgres:16-alpine` container run via podman —
      `alembic upgrade head` created all 4 tables (verified with `psql \dt`); seed run
      twice — first run inserted 6, second run inserted 0 (idempotency proven), `psql`
      SELECT confirms 6 correct rows; `pytest` 4/4 passed against the real DB
      (`test_migrations_create_expected_tables`, `test_seed_is_idempotent`), and 2/4
      pass with the other 2 skipping cleanly when `BEDOUX_DATABASE_URL` is unset;
      `docker-compose.yml` YAML validated. Test container and its volume removed after
      verification — no leftover local state. Known gap: `podman-compose`/docker compose
      plugin isn't installed on this host (`python3 -m pip` has no `pip` module either) —
      full `docker compose up` end-to-end is deferred to P2.5, which owns the Compose
      file anyway.
- [x] P2.3 COMPLETE — `GET /products` (category/search/pagination filters),
      `GET /products/{id}`, `POST /orders` (server computes prices from the DB — client
      cannot submit or tamper with a price), `GET /orders/{id}` confirmation lookup.
      Evidence: 5 new integration tests against a real Postgres — happy path
      (browse → filter → search → detail → order 2 products → confirmation lookup
      returns identical data), unknown-product rejection (400), price-tampering
      resistance (client-sent `unit_price_cents` silently ignored, DB price used),
      404s for missing product/order — `pytest` 9/9 passed total. Also drove the live
      `uvicorn` server with real `curl`: filtered `/products?category=apparel`, ordered
      3 mugs via `POST /orders` → `total_cents: 4200` (1400×3, correct), re-fetched via
      `GET /orders/{id}` and got byte-identical JSON back.
      **Bug caught and fixed during this task:** `price_cents`/`total_cents`/
      `unit_price_cents` were declared `Mapped[int]` but backed by `Numeric(10,0)`,
      which psycopg returns as `Decimal`, not `int` — a real type mismatch that would
      have surfaced as Pydantic coercion oddities later. Changed the columns to
      `Integer` in both `app/models.py` and the (still-unreleased, never applied
      outside this session's throwaway test containers) initial migration file, and
      re-verified against a fresh Postgres instance. No amend of the already-pushed
      P2.2 commit — the fix landed as new work in this task instead.
- [x] P2.4 COMPLETE — `apps/web` (Vite + React 19 + TypeScript, per ADR 0001):
      CatalogPage (list, category filter, search), ProductDetailPage (add to cart),
      CartPage (quantity edit, remove, submit), OrderConfirmationPage; `localStorage`-
      backed client-side cart (`CartContext`); API client with a `/api` base path
      matching the future Kubernetes Ingress routing; Vite dev-server proxy so local
      dev, Compose, and the deployed MVP all address the API the same way; 6 seeded
      product images as placeholder SVGs at `public/static/products/` matching
      `app/seed.py`'s `image_path` values exactly.
      Evidence: `npm run build` (tsc + vite) clean; `npm test` (vitest) 9/9 passed —
      7 cart-logic unit tests + 2 full rendered-DOM flow tests (catalog → product
      detail → add to cart → cart → submit order → confirmation, and a catalog-load
      failure state), driven with `@testing-library/react` + `user-event` (real
      simulated clicks/navigation, not shallow rendering), with `fetch` mocked only at
      the network boundary. **Also verified against real running servers**: booted the
      actual API (with real Postgres + seed data) and the actual Vite dev server
      together, then drove the dev-server's `/api` proxy with `curl` end-to-end —
      `GET /api/products` (6 items), category filter (2 apparel items), a real
      `POST /api/orders` (2× mug → `total_cents: 2800`), and `GET /api/orders/{id}`
      confirmation — an identical network path to what a browser would use.
      **Known verification gap, stated plainly**: no browser-automation tool (e.g.
      Playwright/screenshot) is available in this environment, so the app was never
      *visually* rendered or clicked in an actual browser — `curl`/DOM-test coverage
      is real but is not a substitute for eyes-on browser confirmation. Flagged to the
      owner; a manual click-through in a real browser is recommended before treating
      the golden path as fully proven.
      All test containers, dev/API server processes, and podman volumes torn down
      after verification — confirmed no leftover state (`podman ps -a`, `podman volume
      ls`, `pgrep` all clean).
- [x] P2.5 COMPLETE — `web` service added to `docker-compose.yml` (nginx-unprivileged
      reverse-proxying `/api` to the `api` service by Compose DNS name, mirroring the
      future Kubernetes Ingress); `apps/web/Dockerfile` (node:24-alpine build → nginx
      runtime, non-root uid 101); `apps/api/Dockerfile` fixed to also copy
      `migrations/`+`alembic.ini` (previously missing — a deployed API container
      couldn't have run its own migrations); trivy 0.72.0 installed and both images
      scanned.
      **Findings, fixed for real, not just noted:** API image had 3 HIGH Python-level
      CVEs (`starlette` 0.48.0, pulled in by the narrow `fastapi<0.119` pin from P2.1) →
      bumped to `fastapi>=0.139,<0.140`, eager-upgraded to `starlette` 1.3.1, re-ran the
      full 9-test suite (still 9/9) and rescanned — 0 Python vulns. Web image had 35
      HIGH/CRITICAL CVEs (base `nginx-unprivileged:1.27-alpine` tag had drifted from
      current Alpine patches) → added `apk upgrade` in the runtime stage (temporarily
      `USER root`, then back to the image's non-root `nginx` user) and rescanned —
      0 vulns. 22 OS-level findings remain on the API image's `python:3.12-slim` (debian
      13) base with **no fix available upstream yet** — tracked, not actionable today;
      re-scan in a later phase.
      Sizes after fixes: API 206MB, web 62.4MB.
      Full-stack verification: built both images fresh, ran postgres+api+web as three
      real containers on an isolated podman network (mirroring Compose), ran
      `alembic upgrade head` and the seed script **inside the actual deployed
      container** (not the host venv), confirmed both containers non-root
      (`podman exec ... id`), then drove the published port with `curl` exactly as a
      browser would: catalog (6 products), category filter, and a real order
      round-trip through the nginx `/api` proxy. Caught and fixed two real bugs along
      the way: a registry-path error (`nginxinc/nginx-unprivileged` is not under
      `library/`) and an `npm ci` lockfile-drift failure from crossing glibc→musl
      (fixed by using `npm install` in the Dockerfile, documented inline).
      All containers, the temporary network, image tags, and scan tarballs removed
      after verification — confirmed clean.

**P2 gate approved by owner 2026-07-19** (owner said "approve the gate"; evidence: P2.1–P2.5
above, plus the 2026-07-19 kind/rootless-Podman fix and real-browser verification entries
in the session log). Remaining known issue, not a blocker: 22 unfixed OS-level CVEs on the
API base image, no upstream fix available — see "Known open issues" above.

### P3 — Local Kubernetes

- [x] P3.1 COMPLETE — kind cluster `bedoux` (1 control-plane node, `extraPortMappings`
      `hostPort 8080` → `containerPort 30080`, config at `k8s/kind-config.yaml`), plain
      manifests in `k8s/` (namespace, postgres Deployment+Service+PVC+Secret, api
      Deployment+Service, web Deployment+Service as NodePort 30080 — a stopgap until
      Ingress in P3.3). No probes/limits tuning yet (that's P3.2's scope).
      Evidence: `kind create cluster` (run inside a `systemd-run --user --scope
      --slice=app.slice -p Delegate=yes` wrapper per the fix below) produced a real
      `Ready` node; built `bedoux-api:p3`/`bedoux-web:p3`, loaded via `kind load
      image-archive` (confirmed present with `crictl images` on the node — `kind load
      docker-image` failed with "not present locally" against the podman provider even
      with the correct `localhost/...` tag, so this project uses `podman save` +
      `image-archive` instead, documented in `docs/local-tooling.md`); applied all
      manifests, all 3 pods `Running`; ran `alembic upgrade head` + `python -m app.seed`
      **inside the real deployed API pod** via `kubectl exec` — succeeded on retry after
      first attempt hit `connection refused` (postgres's first-run initdb restart cycle
      wasn't finished yet; there's no readiness probe until P3.2, so `1/1 Ready` only
      reflects the container process starting, not the app being ready — a real gap
      P3.2 exists to close). Verified the golden path against the cluster exactly as
      P2.5 did against Compose: `curl` through the kind hostPort → NodePort → web → api
      chain (catalog, `POST /orders` → `total_cents: 4400` for 2× tote, cross-checked
      directly via `kubectl exec deploy/postgres -- psql` — same order id, same total in
      the real DB); then drove the **same real Chrome browser** (Playwright MCP, from
      the 2026-07-19 browser-verification session) against `http://127.0.0.1:8080/` and
      confirmed the catalog rendered correctly, served entirely from the cluster.
      Cluster, pods, and data are left running (not torn down) — this is the ongoing
      local dev cluster for P3.2–P3.5, unlike the throwaway Compose verification
      containers in earlier phases.
- [x] P3.2 COMPLETE — readiness/liveness probes (postgres: `pg_isready` exec; api/web:
      `httpGet /health` and `/`), resource requests/limits on all three (postgres
      100m/128Mi→500m/256Mi; api 50m/64Mi→250m/256Mi; web 25m/32Mi→100m/64Mi), config
      split into a Secret vs. ConfigMap by whether it embeds a credential
      (`postgres-credentials` Secret gained a `DATABASE_URL` key the api Deployment
      reads via `secretKeyRef`; `web-config` ConfigMap holds the non-secret
      `API_UPSTREAM`), and an `initContainers` entry on the api Deployment
      (`wait-for-postgres`, blocks on `pg_isready` before the main container starts).
      Evidence: `kubectl apply` rolled out clean, all 3 pods `Running`/`1/1`, data
      (6 products, the P3.1 order) intact across the rollout since only Deployments
      changed, not the PVC; catalog re-verified reachable via `curl` through the same
      hostPort chain as P3.1.
      **Real drill, not just config review:** scaled `postgres` to 0 replicas, then
      `kubectl rollout restart deployment/api` — the new pod sat at `Init:0/1` for the
      entire outage instead of racing ahead and crash-looping against a database that
      wasn't there (exactly what happened, uncaught, in P3.1). Scaled `postgres` back to
      1; the instant it was ready, the blocked `api` pod's init container completed and
      the main container started and became `1/1 Ready` — `kubectl wait
      --for=condition=ready` confirmed both transitions. Full stack re-verified healthy
      afterward (catalog `curl` 200, product count still 6).
- [x] P3.3 COMPLETE — ingress-nginx controller (pinned `controller-v1.15.1`, kind-specific
      manifest) + two `Ingress` objects: `bedoux-api` (`/api(/|$)(.*)` prefix-stripped via
      `rewrite-target: /$2`, straight to the `api` Service) and `bedoux-web` (`/` prefix
      to `web`). Split into two `Ingress` objects, not one, because
      `nginx.ingress.kubernetes.io/rewrite-target` applies Ingress-wide, not per-path.
      This also matches the real production shape, not just a kind workaround:
      `docs/architecture.md` already documents the ALB sending traffic straight to pod
      IPs per target group — i.e. path-based routing directly to each Service — so this
      is what P5's ALB Ingress will mirror. `web`'s Service changed from the P3.1
      NodePort stopgap back to ClusterIP; `k8s/kind-config.yaml` gained the
      `ingress-ready=true` node label and port 80/443 `extraPortMappings` the official
      kind ingress guide requires (kept the same host port 8080 → now maps to
      containerPort 80 instead of the old NodePort 30080).
      Evidence: cluster recreated with the new config (normal/expected for kind, not a
      failure — data was re-seeded); ingress-nginx controller pod reached `Ready`;
      `kubectl describe ingress bedoux-api` showed the resolved backend
      `api:8000 (podIP:8000)`; full golden path re-verified through the **Ingress port**
      (same hostPort 8080, now serving via the controller, not the old NodePort):
      `curl` catalog list, single-product lookup (`/api/products/{id}`, confirming the
      rewrite handles nested paths correctly, not just the bare prefix), and a real
      `POST /api/orders` (3× tote → `total_cents: 6600`) cross-checked directly in
      Postgres — same id, same total. Then re-drove the same real Chrome browser
      (Playwright MCP) against the Ingress URL and confirmed the catalog rendered
      correctly (leftover `Cart (2)` badge was expected `localStorage` persistence from
      the browser's throwaway profile, not a bug).
- [x] P3.4 COMPLETE — `charts/bedoux/` Helm chart: templatized versions of all `k8s/`
      resources (postgres, api, web, ingress), plus two hook Jobs per ADR 0005
      (`docs/decisions/0005-helm-migration-hook-job.md`): `bedoux-migrate` (fail-fast
      `alembic upgrade head`) and `bedoux-seed` (opt-in via `--set seed.enabled=true`).
      `values.yaml` parametrizes image tags, replicas, resources, Postgres credentials
      (still the same local-dev-only placeholder), and the migration Job's
      `backoffLimit`/`activeDeadlineSeconds`. `helm lint` clean.
      **Real correction to ADR 0005 found during this task**: the ADR's originally
      accepted hook trigger, `pre-install,pre-upgrade`, is wrong for a fresh install —
      verified live with a second scratch-chart test that a `pre-install` hook runs
      *before* the chart's own non-hook resources exist, so the migration Job's
      `secretKeyRef` to `postgres-credentials` would fail on a genuinely fresh
      `helm install` (confirmed: the scratch test failed with `DeadlineExceeded`, no
      pod ever scheduled). Fixed to **`post-install,pre-upgrade`** — verified this
      combination fires after install-time resources exist, fires before an existing
      release's resources upgrade, and still never fires on rollback (re-confirmed with
      the same scratch-chart method as ADR 0005's original test). ADR 0005 corrected in
      place with the evidence (not superseded — this is a same-day factual correction
      to an implementation detail before any chart depended on it, not a reconsidered
      tradeoff; same discipline as the P2.3 Numeric/Integer fix).
      **Full live verification against the real cluster, not just the scratch chart:**
      deleted the P3.1–P3.3 plain-manifest resources, `helm install`'d the chart fresh
      — migration hook ran correctly against the newly-created Secret, api/web/postgres
      all reached `Ready`; `helm upgrade --set seed.enabled=true` seeded the catalog
      (`bedoux-migrate-1` correctly replaced by `bedoux-migrate-2` via
      `hook-delete-policy: before-hook-creation`); full golden path re-verified through
      Ingress (catalog, a real `POST /api/orders` cross-checked in Postgres, and the
      same real Chrome browser via Playwright MCP). **Deliberate failure drill**: upgraded
      with a nonexistent `api.image.tag` — the `pre-upgrade` migration hook correctly
      failed (`ErrImagePull` → `DeadlineExceeded`), Helm refused the release
      (`UPGRADE FAILED`), and the running app was **never touched** — `api`/`web`/
      `postgres` stayed on the old working revision throughout, confirmed via `curl`
      returning 200 the whole time. `helm history` showed the failed revision recorded
      as `failed` without disturbing the `deployed` one. Recovered with a corrected
      upgrade, then ran a real `helm rollback` (revision 4 → 2) against the live
      app: confirmed via a job-list diff that **no hook fired during rollback**, and
      that all 6 products and the 1 real order survived untouched.
      **Secondary finding recorded, not just noted:** a *failed* hook Job is not
      auto-cleaned by `hook-delete-policy: before-hook-creation` — that policy only
      triggers relative to a successful prior hook of the same name pattern, so a
      failed migration Job (e.g. `bedoux-migrate-3` here) persists until the next
      successful hook of that type runs, or until manually deleted. Worth remembering
      for P8's troubleshooting runbooks.
- [x] P3.5 COMPLETE — four drills against the live Helm-managed cluster, T-201/T-202/
      T-203 evidence below.
      **Scale**: `helm upgrade --set api.replicas=3 --set web.replicas=2` — all 5 pods
      reached `Ready`; `kubectl get endpoints` showed all 3 api pod IPs registered;
      6/6 requests through the Ingress succeeded, confirming the Service actually
      load-balanced across the new pods, not just the original one.
      **Pod deletion**: with `api` at 3 replicas, deleted one pod while firing 20
      requests through the Ingress in parallel — **all 20 returned 200** (zero
      downtime; Kubernetes never removed the deleted pod's traffic share until its
      replacement was scheduled and the other 2 replicas kept serving throughout).
      Separately deleted the single-replica `postgres` pod — confirmed via `psql`
      that all 6 products and the 1 order survived untouched (the PVC, not the pod,
      is what held the data).
      **Broken config, diagnosed from `kubectl` output alone (T-203)**: directly
      `kubectl patch`'d the live `web-config` ConfigMap with a wrong `API_UPSTREAM`
      value (simulating an out-of-band operator mistake, not a chart bug) and
      restarted `web`. Kubernetes' rolling-update safety meant the **old healthy pod
      kept serving traffic** while the new pod entered `CrashLoopBackOff` — the app
      never went down. Diagnosis chain: `kubectl get pods` → `CrashLoopBackOff`;
      `kubectl describe pod` → generic `BackOff` events, not the root cause;
      `kubectl logs` → immediate root cause,
      `nginx: [emerg] host not found in upstream "api-wrong-name"`. Traced that
      hostname back to the ConfigMap, confirmed the drift against the chart's tracked
      value, and fixed it the correct way — `helm upgrade` (not another manual patch)
      to reassert the chart's source of truth. **Real finding**: the ConfigMap value
      alone reverted correctly, but the already-running pods don't restart just
      because a ConfigMap they reference changed — a `kubectl rollout restart` was
      still needed (this chart has no config-checksum-in-pod-annotation trick to
      auto-roll on ConfigMap drift; worth adding if this were a production chart).
      **Rollback**: `helm rollback bedoux 2` — job-list diff confirmed zero hooks
      fired, app stayed reachable, data intact; rolled forward again to the chart's
      current values.yaml state to close out the drill.
      **Second real finding, independent of the drill above**: plain `helm upgrade`
      with **no** `-f`/`--set` flags at all still silently reused the *previous*
      release's user-supplied values (`seed.enabled: true` persisted from an earlier
      `--set` and fired another seed Job) — verified precisely with `helm get
      values`, then confirmed `--reset-values` is what's actually required to return
      to `values.yaml`'s real defaults. This contradicts a naive reading of `helm
      upgrade --help` (which frames reuse as the *opt-in* `--reuse-values`
      behavior) — worth remembering for any future upgrade in this project, and
      worth a callout in P8's troubleshooting runbooks alongside the failed-hook-Job
      cleanup finding from P3.4.
      All four drills run against the real cluster with real `curl`/`kubectl`/`psql`
      evidence above, not simulated or assumed.

**P3 gate approved by owner 2026-07-19** (owner said "approve the gate"; evidence:
P3.1–P3.5 above). No unresolved gaps; the only carry-forward is the project-wide
"Known open issues" list (OS-level CVEs, no fix available) which is unrelated to P3.

### P4 — AWS account readiness

- [x] P4.1 COMPLETE — root MFA + credential review (owner console checklist).
      Evidence (T-301): root MFA enabled; root has no access keys (bootstrap used
      `aws login` browser SSO, a temporary session, never long-lived root keys); new
      IAM user `bedoux-admin` created (group `bedoux-admins`, `PowerUserAccess` +
      scoped custom IAM policy restricted to `bedoux-*`-named resources, not
      `AdministratorAccess`), MFA (passkey) enabled on it;
      `aws sts get-caller-identity --profile bedoux-admin` confirmed
      `arn:aws:iam::<redacted>:user/bedoux-admin` — non-root, as required. Declined
      AWS's bundled "Agent Toolkit for AWS" auto-setup script (would have reinstalled
      the pinned AWS CLI, auto-edited `AGENTS.md`/`CLAUDE.md`, added an unreviewed MCP
      server) and took only the useful `aws login` SSO pattern manually. Full detail:
      `docs/local-tooling.md`'s "AWS CLI identity" section, `docs/PROGRESS.md` Known
      facts above.
- [x] P4.3 COMPLETE — region pinned: **`ca-central-1`** (owner choice, 2026-07-19).
      Recorded under Known facts above.
- [x] P4.2 COMPLETE — budget + alerts + anomaly detection (owner console checklist).
      Evidence: AWS Budgets' standard **"Monthly cost budget" template** created at
      **USD 20**, with its default two thresholds — **80% (USD 16) and 100% (USD 20)**
      of budgeted spend — rather than the four-threshold 5/10/16/20 plan originally
      sketched in `docs/IMPLEMENTATION-PLAN.md`. Accepted as sufficient: 80%/100% still
      covers the same two highest-value tripwires (USD 16 and 20), sessions are
      short/same-day-teardown by design so early 25%/50% warnings matter less here than
      in a long-running account, and **Cost Anomaly Detection** was added as a second,
      independent tripwire (catches unexpected spend *shape*, not just a fixed
      threshold). If earlier warning turns out to matter in practice, add USD 5/10
      threshold notifications to the same budget later — no need to recreate it.
- [x] P4.4 COMPLETE — dry-run of `docs/runbooks/aws-session.md` end-to-end, no AWS
      resources created. Ran every read-only command from both `/aws-session-start`
      and `/aws-teardown-verify` for real against the actual (empty) account with
      `--profile bedoux-admin` / `ca-central-1`: identity confirmed non-root; budget
      confirmed live (`aws budgets describe-budgets` → USD 20 monthly cost budget);
      full leftover-resource sweep (EKS, ALBs, RDS, NAT gateways, EIPs, unattached EBS
      volumes, CloudFormation stacks, running EC2 instances, project-tagged resources)
      — **all empty**, confirming the account genuinely has nothing running and that
      every sweep command is syntactically correct against a real account, not just
      theoretical. Also independently cross-confirmed P4.2's Cost Anomaly Detection via
      CLI (`aws ce get-anomaly-monitors` showed `bedoux-cost-monitor` alongside AWS's
      default monitor).
      **Two real findings from the rehearsal, both fixed:**
      1. `aws ce get-cost-and-usage` returned `DataUnavailableException` — Cost
         Explorer needs ~24h to ingest data on a brand-new account. Not a runbook bug;
         added a caveat to `docs/runbooks/aws-session.md` so this doesn't look like a
         failure next time. The budget check (which doesn't depend on Cost Explorer)
         still worked immediately and is the more reliable pre-session check anyway.
      2. **`docs/HANDOFF.md` had not been regenerated since 2026-07-18** — every
         session across P2, P3, and P4.1-4.3 skipped that closeout step. Regenerated
         it now with accurate current state (through P4.4) and a reminder to check
         `docs/IMPLEMENTATION-PLAN.md`'s pending-decisions section, so a cold-start
         agent session reading `HANDOFF.md` doesn't pick up stale P0/P1-era context.
      `make docs-check` still passes (standing gate).

**P4 gate — APPROVED by owner 2026-07-23. P5 activated.**

### P5 — Manual EKS session

- [x] **P5 pre-work COMPLETE 2026-07-23** — both pending decisions implemented
  before any billable resource: ADR 0006 (Spot risk + gp3 StorageClass) and the
  order-write kill switch + request bounds. See session log entry below.
- [x] **P5.1 COMPLETE 2026-07-28** — session opened, real `eksctl create cluster` +
  nodegroup + OIDC + EBS CSI driver, gp3 dynamic provisioning proven with a real
  volume. Two real IAM findings surfaced and fixed (ADR 0007). See session log
  entries below.
- [x] **P5.2 COMPLETE 2026-07-28** — ECR repos created, images pushed and
  confirmed present. See session log entry below.
- [x] **P5.3 COMPLETE 2026-07-28** — ALB controller live via IRSA, real app
  deployed with real ECR images, reachable via ALB DNS name, golden-path order
  confirmed in Postgres. ADR 0008 (ALB request-path correction) written along
  the way. See session log entry below.
- [x] **P5.4 COMPLETE 2026-07-28** — request trace proven with a correlated
  marker, deliberate breakage diagnosed and fixed, full recovery confirmed.
  See session log entry below.
- [x] **P5.5 COMPLETE 2026-07-28** — full teardown, `/aws-teardown-verify`
  sweep clean, one real finding fixed (undisclosed NAT Gateway). See session
  log entry below.

**P5 gate — APPROVED by owner 2026-07-29; P6 activated.** All of P5.1–P5.5
complete with evidence above. The dedicated gate commit records the approval.

### P6 — Terraform, then CI/CD

- [x] P6.1 COMPLETE — Terraform modules + reviewed no-apply plan. Evidence: session log
      2026-07-29; `terraform fmt -check -recursive`, `terraform validate`, and
      `terraform plan -refresh=false` passed; plan was 26 to add, 0 to change, 0 to
      destroy, with no NAT Gateway/EIP/NAT route resources in source or plan.
- [x] P6.2 COMPLETE — Terraform apply/verify/destroy cycle. Evidence: session log
      2026-07-29T19:37:42Z; live EKS/node/EBS CSI verification, converged plan, and clean
      teardown sweep (T-501).
- [x] P6.3 COMPLETE — GitHub OIDC role declaration + green PR validation pipeline. Evidence:
      PR #1, GitHub Actions run `30579166329` (all four checks pass); ADR 0009; ADR 0010;
      installed local pre-push guardrail blocks direct `main` pushes in this active clone.
- [x] P6.4 COMPLETE — deployment pipeline against session cluster. Evidence: session log
      2026-07-31T17:51:14-06:00; GitHub run `30657784919` passed OIDC/ECR/image push,
      namespace-scoped Helm deploy, and public ALB health/catalog smoke; no-NAT teardown sweep
      confirmed zero temporary resources.
- [x] P6.5 COMPLETE — CI rollback drill. Evidence: session log
      2026-07-31T23:34:32-06:00; GitHub Actions run `30685420148` failed only at its deliberate
      Helm timeout, then passed the corrected rollback/public-health verification and restored a
      healthy release. Final no-NAT teardown sweep clean (T-602).

**P6 gate — APPROVED by owner 2026-08-01; P7 activated.** T-501 (P6.2), T-601 (P6.4; re-proven
in P6.5), and T-602 (P6.5) are recorded. The dedicated gate commit records the approval.

### P7 — Managed data services

- [x] P7.1 COMPLETE — RDS + migration job. Evidence: T-701 passed in the 2026-08-01 short-lived RDS session; migration/seed, one bounded public synthetic order, RDS-backed row count, and clean teardown are recorded below.
- [x] P7.2 COMPLETE — S3 images via adapter + workload identity. Evidence: T-702 passed in
      the 2026-08-02 short-lived session: successful CI migration/seed/rollout and masked
      direct-S3 image smoke, API-pod IRSA caller assertion, policy review limited to
      `s3:GetObject` on `products/*`, and a clean teardown sweep.
- [x] P7.3 COMPLETE — Secrets Manager integration. Evidence: T-703 passed in the 2026-08-03
      short-lived session: direct Secrets Manager retrieval through `bedoux-api-secrets` IRSA,
      migration/seed, API/web rollout, six-product catalog, public health, and clean teardown.
- [x] P7.4 COMPLETE — same-day teardown incl. snapshot policy check. The RDS module policy is
      explicitly `deletion_protection=false`, `skip_final_snapshot=true`,
      `delete_automated_backups=true`, and `backup_retention_period=0`; the existing T-703 live
      sweep recorded zero RDS instances, manual snapshots, automated backups, and subnet groups
      after teardown. No additional AWS session was needed.

### P8 — Observability and drills

- [ ] P8.1 NOT STARTED — app logging + request IDs.
- [ ] P8.2 NOT STARTED — CloudWatch dashboard + alarms.
- [ ] P8.3 NOT STARTED — four troubleshooting drills.
- [ ] P8.4 NOT STARTED — troubleshooting runbooks.

### P9 — Interview package

- [ ] P9.1 NOT STARTED — walkthrough script.
- [ ] P9.2 NOT STARTED — final diagram set.
- [ ] P9.3 NOT STARTED — timed dry-run.

## Blockers

- None. GitHub server-side branch protection remains unavailable while the repository is private
  on its current plan; ADR 0010 documents the accepted local compensating control and its limits.

## Session log

Append newest entries immediately below this heading. Never include secrets or AWS account IDs.

### 2026-08-04T12:14:13-06:00 — P7.4 activated: teardown and snapshot policy review — Codex

- **Phase/task:** P7.4 is **IN PROGRESS** by explicit owner instruction. P7.3/T-703 remains the
  last verified checkpoint; no AWS session is open and no temporary AWS resources are live.
- **Scope:** verify the RDS learning-profile deletion policy and map the already-recorded T-703
  same-day teardown sweep to the P7.4 requirements. Do not create another AWS environment unless
  a required snapshot-policy proof is missing.
- **Next action:** run credential-free Terraform/module checks and inspect the recorded T-703
  evidence; then either complete P7.4 with that evidence or open a fresh owner-approved session
  only if the proof is insufficient.

### 2026-08-04T12:15:30-06:00 — P7.4 complete: snapshot policy and teardown evidence closed — Codex

- **Phase/task:** P7.4 is **COMPLETE**. P7 is now complete at the task level; the P7 phase gate
  remains pending owner approval before P8 work begins. No AWS session is open.
- **Policy evidence:** `infra/terraform/modules/rds/main.tf` keeps the learning profile
  deliberate and cost-bounded: `deletion_protection=false`, `skip_final_snapshot=true`,
  `delete_automated_backups=true`, and `backup_retention_period=0`. Terraform format check and
  credential-free validation passed in the documented `bedoux-aws` toolbox; `bash -n
  scripts/terraform-session-destroy.sh` passed; `make docs-check` passed via the toolbox.
- **Teardown evidence:** the existing live T-703 sweep already recorded zero RDS instances,
  manual snapshots, automated backups, and subnet groups, along with zero other temporary
  resources. The reviewed destroy plan had 23 temporary deletes, zero NAT Gateway deletes, and
  zero persistent ECR deletes; only the persistent allowlist remained.
- **AWS:** none created or destroyed in this closeout validation. Estimated cost: USD 0. No new
  session was opened because the required live teardown evidence already exists.
- **Next action:** owner approval of the P7 phase gate; do not start P8.1 early.

### 2026-08-04T12:21:51-06:00 — P7 gate approved; P8 activated — Codex (owner: Tsogo)

- **Phase/task:** owner explicitly approved the completed P7 gate. P7.1–P7.4 and T-701–T-703
  evidence are recorded; P8 is now active and P8.1 is **NOT STARTED**.
- **Gate record:** this state change is recorded in its own commit with the exact required
  message: `Phase 7 gate approved by owner; activate Phase 8`.
- **AWS:** none. No AWS session was opened and no resources were created or modified.
- **Next action:** begin P8.1 locally; do not open an AWS session until a later P8 task requires
  it and its full runbook preflight is complete.

### 2026-08-03T16:23:26-06:00 — P7.3 T-703 passed; successful Secrets Manager proof and clean teardown — Codex

- **Phase/task:** P7.3 is **COMPLETE**. T-703 is recorded; P7.4 remains **NOT STARTED** pending
  explicit owner activation.
- **Successful workflow:** run `30856761749` on merged `main` completed successfully with
  `use_rds=true`, `use_secrets_manager=true`, `seed_catalog=true`, and `use_s3_images=false`.
  The Helm release deployed at revision 1; API and web deployments rolled out successfully.
- **Credential-boundary evidence:** migration Job and seed Job each completed successfully;
  the API used ServiceAccount `bedoux-api-secrets` with only the Secrets Manager name/region
  environment variables; its IRSA annotation matched the expected role suffix; and the P7.1
  Kubernetes `rds-credentials` Secret was absent. The merged Alembic fix was required after the
  first run exposed its localhost fallback.
- **Public proof:** `/api/health` returned `status=ok` with `orders_enabled=false`; the public
  catalog returned exactly six products. No secret value, database URL, role ARN, account ID, or
  ALB hostname was recorded.
- **T-703 teardown:** Ingress/ALB, Helm release, namespace, and ALB controller were removed.
  The reviewed destroy plan contained 23 temporary deletes, 0 NAT Gateway deletes, and 0
  persistent ECR deletes. Final inventory was zero EKS clusters, RDS instances, manual snapshots,
  automated backups, subnet groups, load balancers, target groups, project VPCs, NAT gateways,
  EIPs, project EBS volumes, self-owned snapshots, project security groups, and temporary
  Secrets Manager objects/IRSA role/policy. The two ECR repositories and one state bucket remained.
- **State/cost hygiene:** persistent Terraform state was re-imported and restored to 19 managed
  persistent resource addresses; the independently scheduled alarm was canceled after clean
  teardown; session-local plans/logs and the out-of-band password variable were removed. The
  preflight budget actual remained below the USD 16 stop threshold.
- **Next action:** owner explicitly activates P7.4 before any P7.4 implementation or AWS session.

### 2026-08-03T15:52:35-06:00 — P7.3 first AWS proof diagnosed; Alembic resolver fix in PR #20 — Codex

- **Phase/task:** P7.3 remains **IN PROGRESS**. The approved, alarmed AWS session is still open;
  no completion or T-703 evidence is claimed.
- **Preflight/apply:** budget actual was below the USD 16 stop threshold; temporary inventory was
  empty before apply. The reviewed Terraform plan had 26 creates, 10 in-place updates, 7 reads or
  no-ops, no deletes/replacements, and zero NAT Gateway changes. Apply completed successfully.
- **Bootstrap evidence:** EKS reached ready state with one node; `gp3` and namespace bootstrap
  succeeded; the ALB controller chart 3.4.3 rolled out; `bedoux-api-secrets` exists with the
  expected IRSA annotation; no Kubernetes `rds-credentials` Secret exists.
- **First workflow:** focused run `30855771120` on merged `main` failed at `Deploy the Helm release`
  with migration Job `BackoffLimitExceeded`. Pod evidence showed the init container had the
  Secrets Manager environment and IRSA web-identity variables, but Alembic attempted the local
  `localhost:5432` default. This isolated a merged-code gap: `migrations/env.py` used
  `settings.database_url` instead of `resolve_database_url()`.
- **Fix:** PR #20 changes Alembic online/offline configuration to use the shared resolver and adds
  a focused wiring regression assertion. All four PR checks passed; the owner must merge PR #20
  before the workflow can be rerun from `main`.
- **Cost/teardown:** the 20:00 MDT alarm remains active. Do not retry until the fix is merged; if
  it is not merged in time, cleanly tear down the live session and record the failed proof.

### 2026-08-03T13:50:25-06:00 — P7.3 local Secrets Manager boundary validated — Codex

- **Phase/task:** P7.3 remains **IN PROGRESS**. The merged P7.2 checkpoint was clean and no
  temporary AWS resources are live.
- **Changed:** added ADR 0012 and a shared API credential resolver. Local/kind profiles retain
  `BEDOUX_DATABASE_URL`; the AWS profile supplies only a Secrets Manager name and region. The
  API, migration hook, and seed hook call the same resolver. Added an opt-in encrypted
  Secrets Manager Terraform module with a temporary `bedoux-api-secrets` IRSA role whose policy
  is limited to `secretsmanager:GetSecretValue` on the exact secret. Added the external Helm
  profile, workflow input/guards, teardown-helper target detection, and the P7.3 session runbook.
- **Local proof:** the focused resolver/image-storage suite passed **10/10** without AWS
  credentials; mocked retrieval asserted the exact secret-name request and malformed documents
  were rejected. Helm lint passed; default, P7.1 Kubernetes-Secret, and P7.3 Secrets Manager
  renders passed. The P7.3 render contained no Kubernetes `Secret`, no `rds-credentials`
  reference, and no `BEDOUX_DATABASE_URL` environment variable; all startup hooks contained
  `resolve_database_url`. Terraform format/credential-free validation passed in the project
  toolbox, workflow YAML parsing passed, teardown-script `bash -n` passed, `make docs-check`
  passed, and `git diff --check` passed.
- **Known host note:** the full API suite was also attempted. Existing FastAPI `TestClient`
  tests hang on this host's Python 3.14/httpx runtime even with a minimal FastAPI app and when
  run alone; this is an environment/runtime limitation, not claimed P7.3 evidence. The focused
  10-test suite is the local evidence for this task, and CI remains the Python 3.12 validation.
- **AWS:** none. Estimated session cost: USD 0.
- **Next action:** review and merge this local implementation, then obtain explicit owner
  approval for a fresh, cost-checked, independently alarmed P7.3 AWS session. Do not create AWS
  resources before walking the full manual preflight in `docs/runbooks/aws-session.md`.

### 2026-08-03T11:48:30-06:00 — P7.3 started: local Secrets Manager boundary — Codex

- **Phase/task:** P7.3 is **IN PROGRESS**. The merged P7.2 checkpoint is clean and no
  temporary AWS resources are live.
- **Scope:** replace P7.1's one-session `rds-credentials` Kubernetes Secret bootstrap with
  direct Secrets Manager retrieval through a dedicated, namespace-bound API ServiceAccount
  and IRSA role. Local/kind and CI validation retain the existing local `DATABASE_URL` path;
  no AWS session is being opened for this implementation step.
- **Architecture note:** the boundary will be recorded in ADR 0012 before completion. API,
  migration, and seed processes will resolve the same JSON `DATABASE_URL` secret through the
  AWS SDK, so the credential is not copied into a Kubernetes Secret. The existing S3 role
  remains a separate session-scoped identity; a combined S3+Secrets session is not silently
  introduced by P7.3.
- **AWS:** none. Estimated session cost: USD 0.
- **Next action:** implement the resolver, Terraform secret/IRSA module, Helm profile, CI
  input, and the P7.3 runbook; then run credential-free local evidence and update this log.

### 2026-08-02T12:55:45-06:00 — P7.2 T-702 passed; clean S3/IRSA teardown — Codex

- **Phase/task:** P7.2 is **COMPLETE**. The owner manually completed the AWS-session
  preflight: non-root `bedoux-admin`, pinned region, spend below the USD 16 stop threshold,
  clean initial inventory, reviewed no-NAT Terraform plan, and an independent 20:00 MDT
  teardown alarm. The reviewed plan created only the temporary no-NAT EKS/RDS learning
  profile plus the P7.2 private product-image bucket, six synthetic SVGs, and scoped API IRSA
  role/policy; no public bucket policy or ACL was present.
- **T-702 evidence:** GitHub Actions run `30761203972` succeeded with RDS, S3-image, and
  catalog-seed modes enabled. It completed the migration/seed, workload rollout, and its public
  smoke: the catalog returned storage-neutral `image_url`; the workflow masked the presigned
  HTTPS URL and fetched the image directly from S3 without logging it. From inside the deployed
  API pod, the STS assertion printed `API IRSA caller identity: expected role`. Terraform policy
  review confirmed only `s3:GetObject` on the temporary bucket's `products/*` prefix.
- **Teardown and hardening:** application release/namespace and controller were removed before the
  guarded session destroy. The reviewed destroy plan had 32 temporary deletes, including the
  product-images bucket, six objects, and image-read IRSA identity; it had zero persistent
  addresses and zero NAT resources. The optional S3 module can be disabled in the normal
  profile, so the destroy helper now detects it in state and explicitly enables it for the
  destruction-only graph. `bash -n` passed and the regenerated plan included the module.
- **Final sweep:** zero EKS clusters, RDS instances/manual snapshots/subnet groups, ALBs/target
  groups, project VPCs/security groups, NAT gateways/EIPs, available project EBS volumes,
  project snapshots, CloudFormation stacks, product-image buckets, image-read role, or image-read
  policy. The session cluster OIDC provider was absent. The persistent GitHub OIDC provider and
  two ECR repositories remain; the single persistent state bucket remains. The scoped IAM policy
  prevents broad IAM enumeration, so the temporary policy and provider checks used direct lookup
  rather than listing. Session-local password, saved plans, and logs were deleted.
- **Cost:** conservatively estimated under USD 4 for this short-lived session; billing data
  lags. No temporary billable resources remain.
- **Next action:** P7.3 is not started. Implement and prove its local Secrets Manager credential
  boundary before requesting a fresh, independently alarmed AWS session.

### 2026-08-02T11:41:28-06:00 — P7.2 approved and local S3-adapter implementation underway — Codex

- **Phase/task:** P7.2 is **IN PROGRESS**. Owner approved the S3 adapter boundary before any
  implementation work. ADR 0011 records the decision: a product keeps a stable `products/...`
  key, the API returns storage-neutral `image_url`, static mode returns `/static/products/...`,
  and S3 mode produces a short-lived presigned `GetObject` URL through the API pod's IRSA
  identity. The frontend has no AWS or storage-provider logic and FastAPI never proxies bytes.
- **Local application:** added the static/S3 URL resolver, explicit S3-mode configuration
  validation, `boto3` runtime dependency, and an Alembic migration that renames the historical
  `image_path` column to `image_key` and converts existing `/static/...` values. The API/web
  contract now exposes `image_url` only. A disposable local PostgreSQL 16 container on
  localhost:5433 ran the migration and the full API suite (**18 passed**, one pre-existing
  FastAPI/TestClient deprecation warning); a downgrade/upgrade cycle converted a seeded legacy
  value back to `products/bottle-001.svg`. The container and its synthetic data were removed.
  Current adapter/config/health tests pass (**8 passed**); web tests pass (**9 passed**) and the
  TypeScript/Vite production build passes.
- **AWS declarations, not applied:** `s3_images_enabled=false` remains the default. Its opt-in
  Terraform module declares a private, AES256-encrypted, versioned, force-destroyable temporary
  bucket; exactly the six version-controlled synthetic SVGs under `products/`; and a temporary
  `bedoux-product-images-role` whose OIDC trust is bound to only
  `system:serviceaccount:bedoux:bedoux-api` and whose policy grants only `s3:GetObject` on that
  bucket's `products/*` prefix. The session-destroy helper explicitly targets this module. Helm
  has a static default and an S3 overlay that preserves an operator-created IRSA ServiceAccount;
  CI checks the required ServiceAccount/ConfigMap and, in S3 mode, masks and fetches the returned
  HTTPS presigned image URL without logging it. `docs/runbooks/p7-2-s3-images-session.md`
  documents the future preflight, bootstrap, T-702 proof, rollback, and teardown sequence.
- **Verification:** `terraform fmt -check -recursive` and offline
  `terraform validate -var=skip_aws_credentials_validation=true` passed. The provider's offline
  mode now supplies inert credentials so validation cannot fall back to the host AWS profile;
  Terraform schema validation had to run outside the filesystem sandbox because provider plugins
  cannot start inside it, not because AWS access was needed. `helm lint`, static and S3 Helm
  renders plus YAML parsing, workflow YAML parsing, `bash -n` plus `--help` for the changed
  teardown helper, `git diff --check`, and `make docs-check` all passed. A real local API image
  build installed `boto3`, completed as the non-root `bedoux` user, and was removed afterward.
- **AWS:** none. No AWS session was opened, no AWS command was run for this task, and no AWS
  resource was created or modified.
- **Next action:** review the local implementation and create a focused PR. P7.2 is not complete
  until a separately approved, fresh AWS session proves T-702 and its final teardown sweep is
  clean.

### 2026-08-01T20:54:25-06:00 — P7.1 T-701 passed against RDS; clean teardown — Codex

- **Phase/task:** P7.1 is **COMPLETE**. T-701 is proven: the real short-lived RDS session ran
  the migration and seed Jobs, served the catalog publicly, and persisted one bounded synthetic
  order through the public application route.
- **Preflight and plan:** owner confirmed actual and forecast AWS spend below USD 16, a 22:00 MDT
  independent teardown alarm was set, and the fresh inventory showed no temporary resources. The
  reviewed `rds_enabled=true` Terraform plan had no NAT Gateway and recreated the temporary VPC,
  EKS 1.34 control plane, one Spot node, EBS CSI, and private encrypted Single-AZ RDS.
- **Normal deployment evidence:** GitHub Actions run `30727844150` passed its OIDC/ECR build,
  external-RDS Helm deployment, migration Job, seed Job, API/web rollout, and public health and
  catalog smoke.
- **Bounded order proof:** the explicit-confirmation verifier created and read back exactly one
  quantity-one synthetic order through the public route. Its trap-protected, six-minute
  kill-switch window restored ordering to disabled; public health then confirmed that state. A
  direct SQLAlchemy query from the API workload confirmed the RDS-backed `orders` row count was
  exactly 1. No endpoint, order identifier, credential, or connection string was retained.
- **Teardown:** started at 20:00 MDT, ahead of the deadline. Ingress/ALB became absent; the Helm
  release, namespace, controller, and temporary storage class were removed. The reviewed destroy
  plan targeted 18 temporary Terraform objects and four RDS-related objects, with zero persistent
  objects. The final sweep found zero EKS clusters, RDS instances/manual snapshots/subnet groups,
  ALBs/target groups, project VPCs/security groups, NAT gateways/EIPs, available EBS volumes,
  self-owned snapshots, or CloudFormation stacks. Persistent ECR repositories and required OIDC/
  IAM deployment roles were directly verified present. All session-local credential and plan/log
  artifacts were deleted.
- **Cost:** this one-session RDS exercise is conservatively estimated at no more than USD 4;
  billing data lags, so the owner must recheck the console before any future AWS session.
- **Next action:** P7.2 remains **NOT STARTED**. Obtain the owner-approved S3 adapter boundary
  described in `docs/IMPLEMENTATION-PLAN.md` before activating it; no AWS action is currently
  authorized.

### 2026-08-01T19:07:59-06:00 — P7.1 bounded synthetic-order rehearsal passed locally — Codex

- **Phase/task:** P7.1 remains **IN PROGRESS**; T-701 still requires the real short-lived RDS
  session. This was the required local rehearsal after the prior deadline overrun.
- **Changed:** added `scripts/verify-order-proof.sh`. It requires explicit
  `BEDOUX_ORDER_PROOF_CONFIRM=1`, checks healthy ordering before writing, creates exactly one
  quantity-one synthetic order, retrieves its confirmation, never prints the base URL or order
  ID, and bounds each connection/request to 5/15 seconds. `--dry-run` makes no HTTP call.
  Updated the P7.1 runbook to use it only inside a time-bounded kill-switch window.
- **Verifier checks:** `bash -n`, `--help`, no-write `--dry-run`, and the missing-confirmation
  refusal all passed.
- **Live local rehearsal:** reused healthy `kind-bedoux` with cached local images. In disposable
  namespace `p7-order-proof`, a local PostgreSQL 16 Service stood in for the external endpoint;
  the external chart profile's migration and seed Jobs completed and PostgreSQL/API/web became
  ready. A 90-second-bounded web Service port-forward ran the verifier once; its successful
  create/read-back path was cross-checked by PostgreSQL `orders` count of exactly 1. Helm release,
  namespace, local database, credential, and port-forward were then removed.
- **AWS:** none. No AWS session or resource mutation ran. Estimated cost: USD 0.
- **Next action:** owner must approve a fresh P7.1 AWS session after a current billing-console
  check. Manually complete preflight, set the independent teardown alarm, review the new plan,
  deploy normally with ordering off, then use the verifier in the bounded proof window before
  timely teardown.

### 2026-08-01T18:55:07-06:00 — P7.1 RDS session torn down; T-701 remains incomplete — Codex

- **Phase/task:** P7.1 remains **IN PROGRESS**; T-701 is **not** claimed. Owner's preflight
  budget check was below USD 16 actual and forecast, but billing data remains delayed.
- **Created and proved:** applied the reviewed no-NAT Terraform plan for the temporary VPC, EKS
  1.34 control plane, one Spot node, EBS CSI add-on, and private RDS. RDS reached `available`;
  the node was `Ready`; EBS CSI controller and node pods were fully ready. Installed the pinned
  ALB controller, created the one-session `rds-credentials` Secret, and dispatched successful
  GitHub Actions run `30715096011`: OIDC/ECR image build, external-RDS Helm deploy, migration
  Job, seed Job, API/web rollout, and public health/non-empty-catalog smoke all passed. Direct
  Kubernetes verification found both hook Jobs `Completed` and API/web `Running`.
- **Missing evidence:** the required single RDS-backed order confirmation was not captured. A
  controlled temporary order-enable attempt produced no confirmation artifact before teardown, so
  no order write is asserted. The namespace deletion removes the temporary credential and makes
  the final kill-switch state immaterial.
- **Timebox incident:** the same-day deadline was 16:00 MDT; teardown began at 18:37 MDT after
  a locally monitored operation outlived its expected timeout. This violated the session
  timebox. Future sessions require an external operator timer and must begin teardown at the
  deadline even if an evidence command is still running.
- **Teardown:** deleted Ingress and confirmed zero ALBs; uninstalled the release and namespace;
  uninstalled the ALB controller and deleted `gp3`; reviewed the targeted destroy plan (18
  deletes: four RDS, no persistent addresses) and applied it. Final sweep: zero EKS clusters,
  RDS instances/manual snapshots/subnet groups, ALBs/target groups, project VPCs/security groups,
  NAT Gateways, unattached EIPs/EBS volumes, self snapshots, and active CloudFormation stacks.
  Direct checks confirmed the two ECR repositories plus the GitHub OIDC provider and five
  allowlisted IAM roles remain. The scoped identity cannot list every OIDC provider, so that
  persistent provider was checked by its known exact identifier instead.
- **Secret hygiene:** removed the temporary master-password file, all saved plans, kubeconfig,
  logs, and request artifacts from `/tmp` after teardown.
- **AWS cost:** provisional conservative working estimate is no more than USD 4; recheck the
  billing console after usage data updates before another AWS session.
- **Next action:** before reopening P7.1, rehearse a bounded order-proof procedure locally and
  use an independently enforced session deadline. Then open a fresh short-lived RDS session only
  after a new preflight and cost check; record a public synthetic-order confirmation before
  teardown to complete T-701.

### 2026-08-01T13:13:00-06:00 — P7.1 RDS Terraform plan reviewed — Codex

- **Phase/task:** P7.1 remains **IN PROGRESS**. A saved plan was created with
  `rds_enabled=true`; its sensitive password is supplied only from the owner-created mode-600
  temporary file and is absent from this evidence.
- **Plan boundary:** 28 creates, 10 updates, and 4 reads; **zero NAT Gateway changes** and no
  unplanned AWS service. The temporary create set is the no-NAT VPC, single-Spot-node EKS,
  EBS CSI add-on/access entries, and the private RDS instance, subnet group, DB security group,
  and one EKS-source-only PostgreSQL ingress rule.
- **RDS review:** PostgreSQL 16.14; encrypted, private, Single-AZ `db.t4g.micro`; fixed 20 GiB
  gp3; zero backup retention; no final snapshot. This matches the short-lived P7.1 design.
- **Persistent-resource review:** the plan applies standard project tags and rebinds the two
  workload IAM-role trust policies to the newly created cluster OIDC issuer, with service-account
  subjects limited to the ALB controller and EBS CSI controller. The GitHub role remains limited
  to the exact repository's `main` subject and `sts.amazonaws.com` audience. The plan also shows
  the existing ECR lifecycle policies and IAM policy attachments as Terraform `create` actions
  because the recovery import helper currently rehydrates their parent resources but not those
  attachment/lifecycle state addresses; it does not introduce an additional repository, role, or
  policy. Their intended bounded lifecycle and least-privilege attachments were reviewed before
  apply.
- **AWS:** plan only; no infrastructure resource was created, modified, or deleted. Estimated
  cost remains USD 0. **Next action:** owner approves applying exactly
  `/tmp/bedoux-p7-1.tfplan`, then observe creation and continue the runbook.

### 2026-08-01T13:01:47-06:00 — P7.1 AWS-session preflight re-established — Codex

- **Phase/task:** P7.1 remains **IN PROGRESS**. Owner reconfirmed the monthly budget's actual
  and forecast are each below USD 16; same-day teardown deadline is 16:00 MDT.
- **Preflight:** fresh `bedoux-admin` CLI credentials authenticated as the documented non-root
  IAM user; region remains pinned to `ca-central-1`. The owner checked billing in the console
  after the CLI billing calls had rejected the expired credential. Current RDS pricing and the
  conservative USD 2–4 session envelope were reviewed.
- **Read-only inventory:** no temporary EKS, RDS instance/snapshot/subnet group, ALB, NAT
  Gateway, unattached elastic IP/EBS volume, or CloudFormation stack exists. Only the two
  allowlisted ECR repositories remain. Terraform was reconnected to the encrypted persistent
  backend and the existing persistent roles, policies, and OIDC provider were imported into
  session state.
- **Teardown readiness:** `scripts/terraform-session-destroy.sh` now states its existing
  `module.rds` target in `--help`; shell syntax and help-text assertion passed. The procedure is
  available before any apply.
- **AWS:** no infrastructure resource was created, modified, or deleted. Estimated cost: USD 0.
- **Next action:** owner makes the one-session RDS master password available only out of band;
  then create and inspect the explicit `rds_enabled=true` Terraform plan. Stop if it contains a
  NAT Gateway, an unplanned service, or a projected total above USD 16.

### 2026-08-01T12:41:35-06:00 — P7.1 AWS-session preflight blocked by expired login — Codex

- **Phase/task:** P7.1 remains **IN PROGRESS**. Owner approved opening its AWS session, but the
  required manual preflight did not complete because the `bedoux-admin` AWS login had expired.
- **Checks attempted:** pinned region configuration reported `ca-central-1`; subsequent identity,
  budget, cost, and temporary-resource inventory calls returned AWS CLI session-expired errors.
  Do not treat the partial output as a valid inventory or budget check.
- **AWS:** no Terraform plan/apply, Kubernetes mutation, or AWS resource mutation ran. Estimated
  cost: USD 0.
- **Next action:** owner reauthenticates `bedoux-admin`; then rerun the entire **Before the
  session** checklist from the start, set the same-day teardown deadline, and review the explicit
  RDS plan before creating resources.

### 2026-08-01T12:31:17-06:00 — P7.1 external-database profile proven locally — Codex

- **Phase/task:** P7.1 remains **IN PROGRESS**. Its external-database migration, seed, catalog,
  and order path is now proven locally; T-701 still requires the later short-lived RDS session.
- **Local-runtime repair:** the old project kind control plane's Kubernetes API was healthy inside
  its container but its rootless-Podman host-port forwarder was absent. A restart exposed an
  unrecoverable `conmon` failure, so the exact broken `bedoux` kind cluster was deleted and
  recreated using `k8s/kind-config.yaml` inside the documented `Delegate=yes` user scope. Its node
  and system Pods then became Ready. This changed local-only project state; it did not contact AWS.
- **Proof:** built fresh local API/web images and loaded them into kind. In disposable namespace
  `p7-rds-test`, a local PostgreSQL 16 service stood in for the external endpoint and an
  `rds-credentials` Secret supplied the SQLAlchemy URL. Helm installed the external profile (no
  in-cluster Postgres Deployment); migration and seed hook Jobs both completed; API, web, and the
  local database were Ready. An API-pod request returned six catalog products and submitted two
  orders (the first command continued after its tool window, then the explicit verification made
  the second); PostgreSQL confirmed two persisted rows. This proves the migration and app use the
  external Secret URL end-to-end, not merely a rendered template.
- **Local teardown:** `helm uninstall p7-rds` and `kubectl delete namespace p7-rds-test` completed;
  follow-up checks returned namespace/release not found. The rebuilt `kind-bedoux` cluster remains
  as the project local-development cluster; no disposable P7 workload remains.
- **AWS:** none. No AWS session opened and no AWS resource was created, modified, or deleted.
  Estimated cost: USD 0.
- **Next action:** manually complete the **Before the session** checklist in `aws-session.md`, set
  a same-day deadline, and review an `rds_enabled=true` Terraform plan before the short-lived
  RDS T-701 exercise.

### 2026-08-01T12:15:10-06:00 — P7.1 local RDS and migration-job implementation checkpoint — Codex

- **Phase/task:** P7.1 remains **IN PROGRESS**. Added a disabled-by-default Terraform RDS module
  and an external-database Helm profile; no AWS plan, apply, or session was opened.
- **Changed:** the RDS module describes an encrypted, private, Single-AZ PostgreSQL 16.14
  `db.t4g.micro` with fixed 20 GiB gp3 storage, no backup/final snapshot, and TCP 5432 ingress
  only from the EKS cluster security group. `rds_enabled=false` preserves P6 sessions. The chart
  now has one `DATABASE_URL` Secret interface: in-cluster Postgres remains the default, while
  `values-aws-rds.yaml` removes the Postgres workload and consumes a pre-created
  `rds-credentials` Secret. API, migration, and seed readiness now use the API image's own
  SQLAlchemy `SELECT 1`, so they test the same URL dialect as the workload rather than trying to
  pass `postgresql+psycopg://` to `pg_isready`. CI renders the new profile and its manual
  workflow input refuses RDS mode unless the Secret exists. P7.3 remains the owner of replacing
  this one-session Kubernetes Secret with Secrets Manager.
- **Validated:** `terraform fmt -check -recursive`; credential-free `terraform validate`;
  `helm lint`; default/AWS/RDS Helm render plus YAML parse (external mode omitted the Postgres
  Deployment and retained API); workflow YAML parse; teardown-script shell syntax; `make
  docs-check`; and `git diff --check` all passed.
- **Local live-test status:** the pre-existing `kind-bedoux` control-plane container reports
  running but its refreshed localhost API endpoint refuses connections. A separate disposable
  `p7-rds` kind cluster was attempted through the documented `Delegate=yes` rootless-Podman
  scope; its control plane never became reachable and was deleted. Both attempts failed before a
  namespace, Secret, database, or Helm release was created. This is a local cluster-runtime
  blocker, not passing T-701 evidence; no workaround is claimed.
- **AWS:** none. No AWS resources created, modified, or deleted. Estimated cost: USD 0.
- **Next action:** review the focused P7.1 implementation, repair/recreate the local kind
  runtime, then run the external-profile migration/seed/order proof before opening an explicit,
  time-bounded P7 AWS session.

### 2026-08-01T11:48:18-06:00 — P6 gate approved; P7 activated — Codex

- **Phase/task:** owner explicitly approved the P6 gate. P6 is complete; P7 is active and P7.1
  (RDS module, connectivity, and migration-job work) is the only in-progress task.
- **Evidence:** T-501, T-601, and T-602 were already recorded in the completed P6.2, P6.4, and
  P6.5 entries. PR #10 merged the final P6.5 rollback and teardown evidence before this approval.
- **Verification:** local `main` was fast-forwarded to merged PR #10 before this gate change; its
  authoritative progress checkpoint records no temporary AWS resources following the clean P6.5
  teardown sweep.
- **AWS:** none. No AWS session opened and no resources created, modified, or deleted. Estimated
  cost: USD 0.
- **Next action:** begin P7.1 locally. Do not start P7.2 until the pending S3 adapter boundary is
  recorded and implemented as specified in `docs/IMPLEMENTATION-PLAN.md`.

### 2026-07-31T23:34:32-06:00 — P6.5 complete: CI atomic rollback evidence and clean teardown — Codex

- **Phase/task:** P6.5 is **COMPLETE**; T-602 is met. The P6 phase gate is now awaiting explicit
  owner approval. This session was manually opened from the full `aws-session.md` preflight with
  a same-day teardown target of `2026-07-31T23:55:00-06:00`; teardown completed before it.
- **Preflight/plan:** confirmed non-root `bedoux-admin`, pinned `ca-central-1`, USD 0 actual of
  the USD 20 budget (Cost Explorer remains lag-prone), and an empty temporary inventory. The
  reviewed Terraform plan had 24 creates, ten expected reconciliation updates, and zero NAT
  Gateway resources. The EKS 1.34 control plane, one Spot node, and EBS CSI add-on became active;
  live Kubernetes checks showed the node and all CSI pods Ready, and no NAT Gateway existed.
- **Green baseline:** GitHub Actions run `30685274638` passed OIDC, immutable-image reuse,
  namespace-scoped EKS access, Helm deploy, migration/seed, `gp3` PVC binding, and public ALB
  health/catalog smoke. API, web, and PostgreSQL were all Ready.
- **T-602 drill:** GitHub Actions run `30685420148` captured the actual pre-drill web image,
  intentionally made only the web rollout unavailable, and failed the Helm step at its
  three-minute timeout. Helm `--atomic` recorded failed revision 2 then healthy deployed revision
  3 (rollback to revision 1). The corrected conditional rollback-verification step passed,
  proving the restored deployment matched the captured pre-drill image and its public health
  assertion passed. The workflow's overall failure is therefore expected and is the drill
  evidence, not a deployment incident.
- **Teardown proof:** deleted the Ingress and confirmed its ALB absent; uninstalled the release,
  namespace, and controller. The new helper's `prepare` dry run and state-only `prepare --execute`
  ran successfully; its reviewed plan contained exactly 14 temporary EKS/add-on/VPC deletes and
  no persistent addresses. It removed the node group, control plane, VPC, and captured cluster
  OIDC provider. Final sweep returned zero EKS clusters, project VPCs, ALBs, target groups, NAT
  Gateways, EIPs, available EBS volumes, snapshots, RDS instances/snapshots/subnet groups, and
  CloudFormation stacks. Only allowlisted `bedoux-api` and `bedoux-web` ECR repositories remain.
- **AWS:** temporary no-NAT VPC, EKS 1.34, one Spot node, EBS CSI, controller, application,
  PVC, and ALB created and destroyed. Estimated session cost remains within the USD 2–4 envelope;
  billing data lags.
- **Next action:** owner approves the P6 gate in its own commit, then explicitly activates P7.

### 2026-07-31T22:40:16-06:00 — P6.5 local rollback-evidence and teardown repair validated — Codex

- **Phase/task:** P6.5 remains **IN PROGRESS**. No AWS session is open; no AWS resource was
  created, changed, or deleted during this local repair.
- **Changed:** the deployment workflow now captures the actual web Deployment image before a
  rollback drill, and its post-failure assertion compares the restored Deployment to that captured
  value rather than to the workflow commit. This correctly supports a healthy baseline deployed
  by an earlier commit while retaining the public health assertion.
- **Teardown hardening:** `terraform-session-destroy.sh` now requires an explicit `prepare`
  dry-run and `prepare --execute` state-only step before its saved plan. Preparation captures the
  cluster OIDC provider, detaches the persistent allowlist and cluster OIDC provider from
  Terraform state, and then permits a target plan limited to temporary EKS/add-on/VPC resources.
  Its apply removes the captured provider only after the cluster. The persistent-state detach now
  tolerates already-detached addresses and reads Terraform state once.
- **Verified:** shell syntax checks; both helper help paths; the no-write detach path against the
  now-empty session state (all allowlisted addresses reported already detached); workflow YAML
  parse; `helm lint charts/bedoux`; `make docs-check`; and `git diff --check` all passed.
- **AWS:** none. Estimated cost: USD 0.
- **Next action:** publish/review this focused repair. After merge, manually open a fresh,
  time-bounded AWS session and rerun the controlled drill to capture final T-602 evidence.

### 2026-07-31T22:34:55-06:00 — P6.5 rollback exercised; evidence assertion and teardown helper need repair — Codex

- **Phase/task:** P6.5 remains **IN PROGRESS**; T-602 is **not** checked off. The session's
  stated 21:00 MDT teardown target was exceeded while the workflow was in its bounded Helm
  timeout, so no further drill retries were attempted and teardown took priority.
- **Controlled drill:** after PR #8 merged, GitHub Actions run `30682672193` reused immutable
  images, obtained main-bound OIDC credentials, and reached the intended Helm upgrade. The
  deliberately unavailable web image made revision 2 fail on its three-minute timeout; Helm
  `--atomic` then restored a healthy deployed revision 3 (rollback to revision 1). The workflow
  evidence step recorded that history, deployed status, and all API/web/PostgreSQL workloads
  Ready, then failed before its public smoke check.
- **Why this is not T-602 evidence:** the evidence step asserted that the restored web image
  matched the current workflow commit. The healthy baseline was from an earlier commit, so
  atomic rollback correctly restored that earlier image instead. The next workflow repair must
  capture the pre-drill web image before Helm and compare the restored deployment to that value;
  it must retain the public health assertion.
- **Teardown finding and recovery:** `terraform-session-destroy.sh plan` correctly refused its
  first saved plan because Terraform's dependency graph included persistent workload-IAM roles.
  To preserve those resources, the allowlisted IAM/ECR state and cluster OIDC-provider state were
  detached first (state-only), then a newly reviewed plan contained 14 temporary EKS/add-on/VPC
  resources only. That plan applied, and the exact captured cluster OIDC provider was deleted
  after the cluster. The helper needs this safe ordering built in before another session.
- **Teardown evidence:** deleted the Ingress and confirmed its ALB absent; uninstalled the
  release, namespace, and controller; then removed the node group, EKS control plane, add-on,
  VPC, and cluster OIDC provider. Final read-only sweep returned zero project VPCs, ALBs, target
  groups, NAT Gateways, EIPs, available EBS volumes, snapshots, RDS instances/snapshots/subnet
  groups, and CloudFormation stacks. Only allowlisted `bedoux-api` and `bedoux-web` ECR
  repositories remain.
- **AWS:** temporary no-NAT VPC, EKS 1.34, one Spot node, EBS CSI, controller, application,
  PVC, and ALB created and destroyed in this session. Estimated cost remains within the planned
  USD 2–4 envelope; billing data lags.
- **Next action:** repair the pre-drill-image evidence assertion and teardown-helper ordering
  locally, validate/review them, then open a fresh time-bounded session for the final T-602 run.

### 2026-07-31T18:59:13-06:00 — P6.5 healthy CI baseline; drill precondition bug found — Codex

- **Phase/task:** P6.5 remains **IN PROGRESS**; same-day teardown target remains
  `2026-07-31T21:00:00-06:00`.
- **Infrastructure/verification:** the reviewed no-NAT Terraform plan applied and then produced a
  clean no-change plan. EKS 1.34, one Spot node, and the EBS CSI add-on are `ACTIVE`; a live
  Kubernetes check confirmed the node and all CSI controller/node pods ready. Operator bootstrap
  created namespace `bedoux`, `gp3` StorageClass, and the pinned ALB controller with its
  Terraform-managed IRSA role. No NAT Gateway exists.
- **Healthy baseline:** GitHub Actions run `30676641212` passed OIDC, ECR image publish,
  namespace-only Helm deploy, migration/seed, and public ALB health/catalog smoke. Locally, the
  release is Helm revision 1 with API/web/Postgres ready and the `gp3` PVC bound. This host's DNS
  initially lagged the ALB hostname, while the runner's built-in bounded retry passed; that is a
  local resolver observation, not a deployment failure.
- **First drill result (not T-602 evidence):** run `30676825495` failed before Helm because it
  attempted to re-push the already-existing immutable commit tag. The conditional evidence step
  also ran without kubeconfig because it was keyed to any failure. Helm history stayed at the
  healthy deployed revision 1; no workload rollback occurred and the app remained healthy.
- **Repair prepared:** workflow now reuses an existing immutable image after an ECR
  `DescribeImages` check (already permitted by the scoped CI role), and only runs rollback
  evidence when the identified Helm step itself failed. This preserves immutable tags and makes a
  same-commit drill reach the intended web rollout failure.
- **AWS:** created the temporary resources listed in the checkpoint; no NAT, RDS, or EIP. No
  resources destroyed yet.
- **Next action:** merge the focused workflow repair, retry the controlled drill, record actual
  T-602 evidence, then use `terraform-session-destroy.sh` and the full teardown sweep.

### 2026-07-31T18:23:49-06:00 — P6.5 rollback-drill session opened; preflight passed — Codex

- **Phase/task:** P6.5 remains **IN PROGRESS**. This session was manually opened by walking every
  **Before the session** item in `docs/runbooks/aws-session.md`; teardown target is
  `2026-07-31T21:00:00-06:00`.
- **Identity/cost/region:** confirmed the non-root `bedoux-admin` IAM user and pinned
  `ca-central-1` region. Budget actual was USD 0.581 against the USD 20 cap; Cost Explorer still
  showed delayed near-zero data, so the budget value is the applicable guardrail. The projected
  USD 2–4 learning-session envelope remains below the USD 16 stop condition.
- **Inventory:** EKS clusters, ALBs/target groups, RDS, NAT Gateways, EIPs, unattached EBS
  volumes/snapshots, and CloudFormation stacks were all empty. No unexplained resource exists.
- **Plan/teardown:** initialized Terraform and imported the persistent ECR/IAM allowlist into
  Terraform state only (no AWS resource creation). The saved P6.5 plan reports 25 creates and
  nine reconciliation changes, zero deletes, and zero `aws_nat_gateway` resources; it recreates
  the absent no-cost EBS CSI role as expected. `terraform-session-destroy.sh --help` succeeded;
  persistent exceptions remain the state bucket, ECR repositories, and no-hourly-cost IAM/OIDC
  identities.
- **Drill preparation:** added a reviewed workflow input that deliberately makes only the web
  rollout use a unique unavailable image tag after the migration hook succeeds. Its conditional
  post-failure step captures Helm/workload evidence and asserts the atomic rollback restored the
  healthy web image and public health endpoint. Local YAML parsing, Helm lint/render,
  `make docs-check`, and `git diff --check` passed.
- **AWS:** no resource created, modified, or deleted. Terraform state attachment only.
- **Next action:** merge the P6.5 workflow/runbook change; then apply this reviewed plan, complete
  operator-only bootstrap, run a green release and the controlled rollback drill, and complete
  the full teardown sweep by the stated target.

### 2026-07-31T18:14:23-06:00 — P6.5 local teardown-recovery repair validated — Codex

- **Phase/task:** P6.5 remains **IN PROGRESS**. No AWS session is open; no AWS command or
  resource action occurred in this task.
- **Changed:** added `scripts/terraform-session-destroy.sh`. Its no-write `plan` path captures
  the cluster OIDC provider, creates a saved destruction plan limited to EKS/add-on/access and
  VPC targets, and refuses any plan containing a persistent ECR/IAM address. Its explicit apply
  deletes that cluster OIDC provider only after the cluster is gone, then detaches persistent
  state. The P6.4 runbook uses this helper. The existing persistent-state importer now conditionally
  imports the EBS CSI role, ALB controller role, and ALB policy, so a missing no-cost identity is
  recreated by Terraform instead of making the next session's import fail.
- **Verified:** `bash -n` for both scripts; each `--help`; persistent importer no-write output;
  static assertions for the workload-IAM exclusion and persistent-address plan refusal;
  `git diff --check`; and direct documentation checks all passed.
- **Next action:** publish and review this local repair. A new AWS session must not begin until
  the repair is merged and its plan path is reviewed.

### 2026-07-31T18:11:25-06:00 — P6.5 started: teardown-recovery hardening first — Codex

- **Phase/task:** P6.5 is **IN PROGRESS**. No AWS session is open and no AWS command has run in
  this task. The P6.4 final inventory remains the authoritative last AWS evidence.
- **Scope:** first make `terraform-persistent-state.sh` conditional for every allowlisted identity
  that can be absent, and add a local, testable teardown plan that cannot select a persistent IAM
  role through a targeted dependency. This directly addresses P6.4's prolonged teardown and the
  deleted EBS CSI role before any rollback drill can create temporary resources.
- **Workspace note:** found an unrelated one-line local edit in
  `docs/IMPLEMENTATION-PLAN.md`; it is preserved and out of scope.
- **Next action:** inspect the helper's full import/detach behavior and Terraform dependency
  graph, then implement the smallest local-only repair with dry-run tests.

### 2026-07-31T17:51:14-06:00 — P6.4 complete: live CI deployment and teardown evidence — Codex

- **Phase/task:** P6.4 is **COMPLETE**. The third main-branch deployment workflow run
  `30657784919` passed every step: GitHub OIDC credentials, ECR authentication, immutable API/web
  image push, namespace-scoped EKS access, Helm deploy with migration and optional seed jobs, and
  public ALB health plus non-empty catalog smoke.
- **Platform proof:** the session operator rendered and created `gp3` once after EBS CSI became
  active; CI remained restricted to namespace `bedoux` and explicitly omitted the cluster-scoped
  StorageClass. PostgreSQL PVC bound through `ebs.csi.aws.com` with
  `WaitForFirstConsumer`; API, web, and PostgreSQL became Ready; the ALB was created only for the
  smoke window. Earlier OIDC evidence exposed the organization's custom subject template, and
  Terraform now accepts the exact repository-and-main-bound subject without widening role scope.
- **Teardown:** deleted the Ingress and verified its ALB absent, uninstalled the application and
  controller, removed the namespace, and destroyed the temporary EKS/add-on/access/VPC resources.
  Final read-only sweep: zero EKS clusters, ALBs, target groups, RDS instances/snapshots/subnet
  groups, NAT Gateways, EIPs, available EBS volumes/snapshots, project VPCs/instances, and
  CloudFormation stacks; state bucket and two ECR repositories remain.
- **Operational finding:** Terraform 1.15 failed to construct a normal destroy graph after the
  persistent-state detach. A targeted recovery destroy completed but, through a dependency on the
  EKS OIDC provider, also deleted the EBS CSI role. The role is no-cost and absent rather than
  orphaned; Terraform will recreate it next session. The session exceeded its intended 14:00
  teardown target while that recovery ran, so P6.5 must first harden this teardown path before
  any drill.
- **Next action:** P6.5 is **NOT STARTED**. Open a fresh, time-bounded session only after a
  reviewed teardown-recovery fix; do not create AWS resources in the meantime.

### 2026-07-31T12:58:41-06:00 — P6.4 OIDC repair proved; Helm stopped at cluster-scope boundary — Codex

- **Phase/task:** P6.4 remains **IN PROGRESS**. Owner merged the focused OIDC trust repair,
  then Terraform applied its reviewed plan: **0 add, 1 change, 0 destroy**. A read-only IAM check
  confirmed the live condition matches the merged source.
- **Deployment evidence:** main workflow run `30657130536` completed GitHub OIDC authentication,
  ECR authentication, and immutable API/web image build/push. Namespace-scoped EKS access also
  succeeded. Helm then stopped before creating a release because the chart attempted to read the
  cluster-scoped `gp3` StorageClass, while the deployment role intentionally has edit access only
  in namespace `bedoux`. Its atomic install left no Helm release, PVC, StorageClass, or ALB.
- **Safe repair proposed:** retain the least-privilege CI boundary. As the session operator,
  bootstrap the chart-rendered `gp3` StorageClass once after the EBS CSI add-on is active; change
  the CI Helm invocation to set `storageClass.create=false`; add the operator step and rationale
  to the P6.4 runbook. Do **not** grant cluster-scoped StorageClass access to CI.
- **Approved repair/validation:** owner approved the focused operator-bootstrap approach. CI now
  sets `storageClass.create=false`; the runbook renders and creates `gp3` once as the operator.
  Local workflow assertions, Helm lint, client-side validation of the rendered operator manifest,
  a CI render proving no StorageClass, documentation checks, and `git diff --check` passed.
- **Next action:** merge the focused repair, create `gp3` from the documented chart render, then
  rerun the manually dispatched workflow. If that cannot complete before
  `2026-07-31T14:00:00-06:00`, start the documented teardown.

### 2026-07-31T12:22:44-06:00 — P6.4 GitHub OIDC custom-subject mismatch isolated — Codex

- **Phase/task:** P6.4 remains **IN PROGRESS**. After owner merge `84e4a77`, dispatched the
  manually selected `main` workflow with catalog seeding. Its diagnostic completed and the AWS
  credential action retried then failed safely. ECR authentication, image builds/pushes, EKS
  access, Helm deployment, and ALB smoke testing were all skipped; no application release, ALB,
  or image was created.
- **Evidence:** workflow run `30654318696` emitted the expected GitHub OIDC issuer and audience,
  and an exact subject bound to this repository and `refs/heads/main` but formatted through the
  organization's custom numeric-ID subject template. The live Terraform-managed trust policy
  instead expected the standard name-based GitHub subject, causing the STS denial.
- **Repair/plan:** replaced only the Terraform trust-subject input with the exact observed custom
  subject; issuer, audience, role permissions, EKS namespace access, and all other resources are
  unchanged. Offline Terraform validation passed. The saved live plan is exactly **0 add, 1
  change, 0 destroy**: an in-place update of `bedoux-github-actions-role`'s subject condition.
- **Next action:** validate/publish/merge the focused source repair, apply only the reviewed plan,
  verify the live condition, then immediately dispatch the main-branch workflow again. Keep the
  hard teardown deadline `2026-07-31T14:00:00-06:00`; do not extend it for troubleshooting.

### 2026-07-31T12:01:14-06:00 — P6.4 OIDC claim diagnostic published and validated — Codex

- **Phase/task:** P6.4 remains **IN PROGRESS**. The approved diagnostic is PR #2, `Fix P6.4
  OIDC: add claim diagnostic`; its four pull-request validation jobs are green: API tests,
  container build and scan, Terraform and Helm validation, and web lint/test/build.
- **Verified:** local workflow YAML/control assertions, a JWT-payload decoding fixture, direct
  documentation checks, and `git diff --check` passed before publication. The PR contains the
  time-bounded session evidence and does not contain a token, role ARN, or account identifier.
- **Next action:** the owner merges PR #2 to `main`, which is necessary because the AWS trust
  condition deliberately permits only the main branch. Immediately rerun the manually dispatched
  workflow and capture its issuer/audience/subject evidence. If main cannot be updated and
  exercised before `2026-07-31T14:00:00-06:00`, begin teardown instead.

### 2026-07-31T11:54:59-06:00 — P6.4 non-sensitive OIDC claim diagnostic approved — Codex

- **Phase/task:** P6.4 remains **IN PROGRESS** and the temporary session environment described
  above remains live. The owner approved a narrowly scoped workflow diagnostic following the
  first failed main-branch deployment.
- **Changed:** before the AWS credentials action, the manually dispatched workflow now requests
  its GitHub OIDC token and decodes only its issuer (`iss`), audience (`aud`), and subject (`sub`)
  claims. It does not print the token, request token, role ARN, account identifier, or any AWS
  credential. The next run will therefore establish whether the GitHub token really matches the
  Terraform-declared branch-bound AWS trust condition.
- **Runbook correction:** pinned the AWS Load Balancer Controller chart at `3.4.3` and made its
  `vpcId` explicit. The first install's metadata VPC discovery timed out in this public-only
  profile; the corrected Helm revision is healthy with two ready controller pods.
- **Next action:** validate and publish this focused change, merge it to `main`, and rerun the
  deployment while the controlled session is still active. If that cannot happen safely before
  `2026-07-31T14:00:00-06:00`, start the documented teardown immediately.

### 2026-07-31T11:38:57-06:00 — P6.4 OIDC deployment failure diagnosed to trust-token boundary — Codex

- **Phase/task:** P6.4 remains **IN PROGRESS**. Terraform applied the exact no-NAT reviewed plan
  and then converged with no further changes: EKS 1.34 is active, one Spot node is Ready, EBS CSI
  is active at `v1.63.0-eksbuild.1`, and four EKS access entries exist. The operator created the
  required `bedoux` namespace.
- **Controller finding/fix:** the initial pinned ALB-controller 3.4.3 install failed cleanly
  because this profile's controller could not discover the VPC through instance metadata. Logs
  identified the exact VPC-ID discovery timeout; no IAM broadening was attempted. The runbook now
  derives `vpcId` from Terraform output. Helm release revision 2, with that explicit VPC ID and
  the existing IRSA role, is deployed with two ready controller pods.
- **CI result:** repository variable `AWS_DEPLOY_ROLE_ARN` was set from Terraform output and the
  `main` workflow was dispatched with fresh-catalog seeding enabled. GitHub run `30651679254`
  failed safely at `Configure short-lived AWS credentials through GitHub OIDC` after retries with
  `Not authorized to perform sts:AssumeRoleWithWebIdentity`; ECR login, image build/push, Helm
  release, and ALB smoke test were all skipped. Therefore no application release, public ALB, or
  new ECR image exists.
- **Read-only diagnosis:** the live provider has `sts.amazonaws.com` as its client ID; the live
  role trust requires that audience and the exact `main`-branch subject. They match the intended
  configuration, but do not explain the STS denial. The next safe diagnostic is a minimal workflow
  step that requests the GitHub token and prints only its non-secret `iss`, `aud`, and `sub`
  claims before the authentication action; it requires an owner-approved source change and merge.
- **AWS:** temporary cluster/controller resources are live for the same-day session; persistent
  GitHub OIDC identity resources were created as planned. Estimated session spend remains within
  the USD 2–4 envelope; teardown target is `2026-07-31T14:00:00-06:00`.
- **Next action:** owner approves the focused diagnostic change promptly, or directs immediate
  teardown. Do not bypass CI with administrator credentials or broaden the deployment role.

### 2026-07-31T11:02:58-06:00 — P6.4 AWS-session preflight complete — Codex

- **Phase/task:** P6.4 remains **IN PROGRESS**. The manual **Before the session** checklist in
  `docs/runbooks/aws-session.md` was completed before any AWS mutation. Same-day teardown target:
  `2026-07-31T14:00:00-06:00`.
- **Identity/cost:** confirmed non-root `bedoux-admin` identity and pinned `ca-central-1` region.
  Budget limit is USD 20; actual is USD 0.581 with no forecast returned. Latest observed Linux
  `t3.medium` Spot price was USD 0.0181/hour. AWS's current standard-support EKS fee is USD
  0.10/cluster-hour; the ALB also bills by hour plus LCU usage. The three-hour session remains in
  the documented conservative USD 2–4 envelope and below the USD 16 stop condition.
- **Inventory:** no EKS clusters, ALBs, target groups, RDS instances, available/pending NAT
  Gateways, EIPs, unattached EBS volumes, project VPCs, project instances, or CloudFormation
  stacks. Tagged persistent inventory is exactly the state S3 bucket and two ECR repositories;
  four allowed IAM roles and the ALB-controller policy exist. The GitHub OIDC provider is absent
  as expected before P6.4's first apply. Broad IAM listing actions are intentionally denied, so
  exact known-name reads were used instead; no IAM policy was broadened.
- **Plan/destruction path:** initialized remote Terraform state, imported the existing persistent
  resources, and reviewed the saved plan: 27 creates, 7 converging updates, zero NAT Gateway/EIP
  changes. Creates are the short-lived VPC/EKS/node/add-on/access resources plus the new GitHub
  OIDC identity; existing ECR repositories are updates, not re-creations. `terraform plan
  -destroy` is available; after deployment its teardown uses the documented ingress/release
  removal, persistent-state detach, Terraform destroy, and full runbook inventory sweep.
- **Operational finding:** an interrupted local Terraform command briefly left a state-lock race.
  It was diagnosed as this workstation's still-running process. A force-unlock attempt against an
  already-absent old lock made no change; the active lock was not cleared. The process exited, the
  persistent imports converged, and the reviewed plan then acquired state normally. No AWS
  infrastructure was created by this recovery.
- **AWS:** read-only preflight and Terraform state bookkeeping only; no infrastructure created,
  changed, or deleted. Estimated session cost so far: USD 0.
- **Next action:** apply the saved reviewed plan, then verify the EKS cluster, one Spot node, EBS
  CSI add-on, OIDC role, and namespace bootstrap before dispatching CI.

### 2026-07-31T10:51:28-06:00 — P6.4 published checkpoint verified — Codex (owner merge confirmation)

- **Phase/task:** P6.4 remains **IN PROGRESS**. The owner merged PR #1 as merge commit `e26b900`;
  local `main` was fetched and confirmed identical to `origin/main` before this session branch
  was created. This also resolves the discovered publication discrepancy: the owner confirmed the
  former remote `main` had not contained the local P5-gate/P6 work until this merge.
- **Verified/owner evidence:** owner independently reviewed the main-branch-bound OIDC trust,
  least-privilege ECR/EKS role policy, namespace-only EKS access, no-NAT VPC implementation,
  protected Terraform-state-bucket settings, conditional first-session OIDC import behavior,
  full-diff secret/account-identifier sweep, and all four green PR checks before merging.
- **Finding:** recorded the non-blocking ECR lifecycle tag-prefix mismatch above. It is deferred to
  a focused follow-up so P6.4's first controlled deployment remains the sole active work item.
- **AWS:** none created, changed, queried, or deleted. Estimated session cost: USD 0.
- **Next action:** manually execute every **Before the session** preflight item, then present the
  reviewed Terraform plan and regional cost estimate before applying anything.

### 2026-07-31T10:31:00-06:00 — P6.4 local preparation validated in GitHub — Codex

- **Phase/task:** P6.4 remains **IN PROGRESS**. The deployment workflow deliberately remains
  unavailable to AWS until its branch-bound source is merged to `main` and a manual session is
  opened.
- **Verified:** PR #1 GitHub Actions run `30647326143` passed all four `PR validation` jobs:
  API tests (39s), container build and scan (1m02s), Terraform and Helm validation (20s), and
  web lint, test, and build (28s).
- **AWS:** none created, changed, queried, or deleted. Estimated session cost: USD 0.
- **Next action:** owner reviews and merges PR #1 to `main`. Then open the manual P6.4 session
  using `aws-session.md`, create the temporary learning environment from the reviewed Terraform
  plan, and dispatch the main-branch deployment workflow.

### 2026-07-31T10:28:46-06:00 — P6.4 local deployment pipeline prepared — Codex

- **Phase/task:** P6.4 remains **IN PROGRESS**. No AWS session is open and no AWS command has
  run in this task.
- **Changed:** added a manually dispatched deployment workflow that gets a GitHub OIDC token only
  on its selected ref, builds/pushes commit-SHA-tagged API/web images, deploys the AWS Helm
  profile with `--atomic`, and smoke-tests the public ALB health/catalog routes. Added the P6.4
  operator runbook for Terraform apply, namespace and ALB-controller bootstrap, repository role
  variable setup, workflow dispatch, and same-day teardown. Corrected the persistent-state helper
  so the first P6.4 import skips the deliberately absent GitHub OIDC provider/role/policy; the
  reviewed apply creates them, while later sessions import them normally.
- **Verified:** `bash -n scripts/terraform-persistent-state.sh`; helper `import` dry run; workflow
  YAML/control assertions via PyYAML; `helm lint charts/bedoux`; both default and AWS `helm
  template` renders; `terraform fmt -check -recursive`; credential-free `terraform validate
  -var=skip_aws_credentials_validation=true`; direct documentation XML/spine checks; and `git diff
  --check` all passed. The Terraform schema check was run outside the sandbox because the sandbox
  cannot launch the already-installed provider binaries; it made no AWS call.
- **AWS:** none created, changed, queried, or deleted. Estimated session cost: USD 0.
- **Next action:** owner reviews and merges PR #1 to `main`. Only after the workflow is on `main`
  may a P6.4 AWS session manually complete every `aws-session.md` preflight item.

### 2026-07-30T15:50:00-06:00 — P6.3 complete: local guardrail accepted and verified — Codex

- **Phase/task:** P6.3 complete. After GitHub confirmed that its private-repository plan cannot
  enforce rulesets, the owner directed work to continue with the documented compensating control.
- **Changed:** added ADR 0010, a transparent branch-protection/guardrail runbook, and the
  versioned `scripts/git-hooks/pre-push` plus safe installer. The hook rejects a direct local
  `main` push; it does not claim to protect other clones or GitHub's UI.
- **Verified:** script syntax check passed; installer dry-run showed the expected hook target;
  installer completed without overwriting a prior hook. A simulated `main` update exited 1 with
  the refusal message; a simulated feature-branch update exited 0. PR #1's current head passed
  all four `PR validation` jobs. The GitHub ruleset API still returns the expected plan-gated
  response, and classic `main` protection remains absent — exactly the documented limitation.
- **AWS:** none created, changed, or deleted. Estimated session cost: USD 0.
- **Next action:** P6.4 is **NOT STARTED**. Do not create AWS resources until a new session
  manually completes every **Before the session** step in `docs/runbooks/aws-session.md` and a
  reviewed plan/cost/teardown window is recorded.

### 2026-07-30T15:13:39-06:00 — P6.3 branch-protection verification blocked — Codex

- **Phase/task:** P6.3 remains **IN PROGRESS**. Draft PR #1's current head is green, but its
  required check cannot be enforced yet.
- **Verified:** read-only GitHub API inspection returned `403` from the repository rulesets
  endpoint, explicitly stating that rulesets need an eligible plan or a public repository.
  The classic `main` branch-protection endpoint returned `404`, so no classic protection rule is
  active either.
- **Blocker/decision required:** choose one: (1) use a GitHub plan that supports protection for
  this private repository; (2) make the repository public only after the planned history review,
  which requires an explicit ADR because ADR 0004 currently keeps it private until pre-P9; or
  (3) approve and document a compensating local control, such as a reviewed pre-push guardrail,
  acknowledging it is not server-enforced branch protection.
- **AWS:** none created, changed, or deleted. Estimated session cost: USD 0.
- **Next action:** owner selects the control, then its real configuration/evidence is recorded
  before P6.3 is checked complete.

### 2026-07-30T14:27:54-06:00 — P6.3 PR pipeline green — Codex

- **Phase/task:** P6.3 remains **IN PROGRESS** only for the owner-operated branch-protection
  step. Draft PR #1 contains the P6.1/P6.2 checkpoints and P6.3 implementation.
- **Verified:** GitHub Actions run `30579166329` passed all four `PR validation` checks:
  `API tests` (**13 passed**), `Web lint, test, and build`, `Terraform and Helm validation`,
  and `Container build and scan`. The first run correctly exposed stale npm lockfile metadata;
  the focused lockfile repair in commit `dfb6c22` produced this green rerun.
- **AWS:** none created, changed, or deleted. Estimated session cost: USD 0.
- **Next action:** owner completes the exact settings in
  `docs/runbooks/github-branch-protection.md` (required checks, up-to-date branch, conversation
  resolution, force-push/deletion protection, administrators included) and reports confirmation.
  Then record the owner evidence, mark P6.3 complete, and proceed only to P6.4.

### 2026-07-30T14:21:29-06:00 — P6.3 PR #1 lockfile repair — Codex

- **Phase/task:** P6.3 remains **IN PROGRESS**. Draft PR #1's first `PR validation` run
  proved the workflow runs: Terraform/Helm passed; the web job failed before linting because
  `npm ci` found two optional `@emnapi` packages absent from `apps/web/package-lock.json`.
- **Changed:** regenerated only `apps/web/package-lock.json`; it now records the missing
  optional packages required by the existing dependency graph. No application dependency or
  source version changed.
- **Verified:** the exact CI clean-install command, `npm ci`, passed locally; `npm run lint`
  passed with the existing Fast Refresh warning, `npm test` passed **9**, and `npm run build`
  passed. `npm install` reported two high-severity audit findings; no automated audit upgrade
  was applied because that would be unrelated dependency churn outside this focused CI repair.
- **AWS:** none created, changed, or deleted. Estimated session cost: USD 0.
- **Next action:** commit/push the lockfile repair to PR #1 and capture the rerun result. Then
  complete the owner branch-protection checklist before marking P6.3 complete.

### 2026-07-30T13:54:52-06:00 — P6.3 publishing preflight blocked — Codex

- **Phase/task:** P6.3 remains **IN PROGRESS**. No branch, commit, push, pull request, or AWS
  operation was performed in this attempt.
- **Verified:** the working tree contains only the reviewed P6.3 Terraform, workflow, ADR,
  runbook, and progress files; `git diff --check` passes. `gh --version` is available, but
  `gh auth status` reports the active collaborator account's token is invalid.
- **Blocker:** owner must run `gh auth login -h github.com`, select the collaborator account
  with access to this repository, and complete the browser/device authorization. Then rerun
  `gh auth status` successfully before the draft-PR publish flow resumes.
- **AWS:** none created, changed, or deleted. Estimated session cost: USD 0.
- **Next action:** after valid GitHub CLI authentication is confirmed, create the scoped
  `agent/` branch, commit the already reviewed P6.3 work, push it, and open a draft PR for the
  first `PR validation` run.

### 2026-07-30T13:49:55-06:00 — P6.3 OIDC role + PR pipeline implementation — Codex

- **Phase/task:** P6.3 remains **IN PROGRESS** pending its first real pull-request run and
  owner-applied branch protection. No AWS session was opened.
- **Changed:** added Terraform for the GitHub Actions OIDC provider, the
  `bedoux-github-actions-role`, and its narrowly scoped policy: main branch of this repository
  only; ECR upload only to the two Bedoux repositories; EKS cluster description only; EKS edit
  access only in namespace `bedoux`. The provider/role/policy are declared but will first be
  created only in P6.4's runbook-governed session, then retained by the persistent-state helper.
  Added a pull-request-only workflow that runs API tests against a PostgreSQL service, web lint/
  test/build, offline Terraform validation, Helm lint/render for both profiles, and immutable
  candidate image build plus fixable HIGH/CRITICAL Trivy scans. It has `contents: read` only and
  cannot mint an AWS OIDC token. ADR 0009 records the trust and namespace boundary; the new
  branch-protection runbook gives the owner the exact post-green checks to enable.
- **Verified:** credential-free `terraform validate -var=skip_aws_credentials_validation=true`
  and `terraform fmt -check -recursive` passed; `helm lint` passed and both default/AWS Helm
  profiles rendered; API `pytest -q` passed **6**, skipped **7** DB tests without a local DB;
  web `npm run lint` passed with one pre-existing Fast Refresh warning, `npm test` passed **9**,
  and `npm run build` passed. Workflow YAML parses and `git diff --check` passed. `make
  docs-check` remains blocked by the host Podman wrapper (`failed to get the Podman version`),
  while its direct XML/spine checks passed.
- **AWS:** none created, changed, or deleted. Estimated session cost: USD 0.
- **Next action:** review/commit and publish this work, open a pull request to capture the first
  green `PR validation` run, then have the owner complete
  `docs/runbooks/github-branch-protection.md`. Do not create the OIDC provider or role until
  P6.4 opens a manual AWS session.

### 2026-07-30T19:24:40Z — P6.3 EKS support-version correction — Codex

- **Phase/task:** P6.3 remains **IN PROGRESS**. AWS Health reported that EKS 1.33 entered
  extended support after the short-lived P6.2 cluster had already been destroyed; a
  read-only EKS inventory confirmed no live cluster.
- **Changed:** pinned `kubernetes_version` to `1.34` in the Terraform default and example,
  and refreshed current-state documentation. The EBS CSI pin remains
  `v1.63.0-eksbuild.1`: a read-only EKS compatibility query confirmed it is the default
  compatible release for EKS 1.34 in `ca-central-1`.
- **Verified:** `terraform fmt -check -recursive` and `terraform validate` passed. No AWS
  resource was created, changed, or deleted; estimated session cost: USD 0.
- **Next action:** continue P6.3's GitHub OIDC role and PR pipeline implementation.

### 2026-07-29T19:37:42Z — P6.2 complete: Terraform apply/verify/destroy and clean sweep — Codex

- **Phase/task:** P6.2 complete; T-501 met. The manual runbook preflight confirmed the
  non-root `bedoux-admin` identity, pinned `ca-central-1` region, USD 20 budget, and an
  explainable pre-existing inventory. Budget actual was USD 0.35 at the final check.
- **Changed:** added remote-state bootstrap, state-safe persistent-resource
  import/detach helper, EKS-compatible EBS CSI version, exact existing ALB-controller
  policy, and static VPC subnet map (fixes the import graph). The live cycle found the
  EKS creator had no access entry, so the EKS module now creates an explicit access entry
  for the dynamically derived current caller and associates the AWS cluster-admin access
  policy. This is the least-privilege, reproducible replacement for an implicit creator
  mapping; no account identifier is committed.
- **Verified:** initial reviewed plan was **19 add, 7 change, 0 destroy**, with no NAT,
  NAT route, or EIP. After the access correction, `terraform validate`, `terraform fmt
  -check -recursive`, and a converged `terraform plan` all passed. Live verification:
  EKS 1.33, one Spot `t3.medium` node Ready, and EBS CSI add-on `ACTIVE` at
  `v1.63.0-eksbuild.1`; both EBS CSI controller pods were Running. Kubernetes access was
  denied before the explicit entry and succeeded after it, providing a real IAM/bootstrap
  finding and fix.
- **Teardown:** persistent ECR/IAM resources were detached from session state before the
  reviewed destroy plan. Terraform terminal streaming interrupted twice while AWS
  continued asynchronous node-group deletion, leaving stale S3 state locks; each lock was
  cleared only after confirming no Terraform process remained. The final AWS inventory
  confirmed no EKS cluster, tagged VPC/IGW, ALB, target group, NAT Gateway, unattached
  EIP, RDS instance/snapshot/subnet group, unattached EBS volume, EBS snapshot, or active
  Bedoux CloudFormation stack. Historical `eksctl` stacks are `DELETE_COMPLETE`.
- **Persistent allowlist:** exactly the two immutable ECR repositories, the tagged state
  bucket, four named IAM roles, and ALB-controller policy remain. The tag-based inventory
  returned only two ECR mappings and one S3 mapping. Root session state is intentionally
  empty after teardown; any future AWS apply must first run
  `scripts/terraform-persistent-state.sh import --execute`.
- **AWS:** temporary VPC/EKS/node/add-on/OIDC/access resources created and destroyed in
  the same session. Estimated P6.2 cost: below USD 0.10; billing telemetry is lagged.
- **Next action:** P6.3 — GitHub OIDC role + PR pipeline (local/GitHub work only; do not
  open an AWS session unless a later step actually requires AWS mutation).

### 2026-07-29 — P6.2 partial apply paused for credential renewal — Codex

- **Phase/task:** P6.2 remains **IN PROGRESS**. The manual `aws-session.md` preflight
  completed with the non-root `bedoux-admin` identity, the pinned `ca-central-1` region,
  budget below the USD 20 guardrail, no unexpected pre-existing regional resources, and a
  reviewed Terraform plan. Persistent P5 ECR/IAM resources were imported into remote
  Terraform state; a versioned, encrypted, public-blocked S3 state bucket was created as
  an approved persistent exception.
- **Changed:** added the remote-state bootstrap and state-safe persistent-resource
  import/detach helper; corrected the VPC route-association graph; pinned the
  EKS-compatible EBS CSI add-on release; and vendored the existing ALB controller policy
  exactly so Terraform updates its tags rather than replacing it. `terraform fmt -check
  -recursive` and `terraform validate` passed. The reviewed apply plan was **19 to add,
  7 to change, 0 to destroy**, with no NAT Gateway, NAT route, or EIP resource.
- **AWS:** the first apply terminal stream ended early and left a stale state lock. After
  confirming no Terraform process remained, the specific stale lock was released and a
  fresh plan was reviewed (**9 to add, 2 to change, 0 to destroy**). The resumed apply
  failed before EKS creation because the second public subnet CIDR conflicted with a
  subnet already in the new VPC. The remote state currently tracks the VPC, Internet
  Gateway, public route table, one public subnet, required ECR lifecycle/tag updates,
  and IAM policy attachments; the second subnet may exist outside state and must be
  inventoried. No EKS cluster/node group, ALB, NAT Gateway, or Elastic IP was created.
- **Stop condition:** immediately after the failure, `aws ec2 describe-subnets` returned
  an expired-session error. No further AWS calls or mutations were attempted. This is a
  pause for credential renewal, not permission to continue without the runbook.
- **Next action:** renew authentication, manually repeat the runbook's **Before the
  session** checklist, inspect the VPC's subnets, import any untracked subnet if present,
  then produce a fresh plan. Complete verification and the teardown sweep in the same
  renewed session before marking P6.2 complete.

### 2026-07-29 — P5 gate checkpoint verification — Codex

- **Phase/task:** P5 gate remains active and awaits explicit owner approval; P6 was not
  activated and no later-phase work started.
- **Changed:** no implementation or architecture files. This entry records the required
  checkpoint verification only.
- **Verification:** `git status --short` was clean and `git log --oneline -5` confirmed
  `1e9529e` (`P5.5 complete: full teardown, ...`) remains the latest task checkpoint.
  Read-only AWS checks, using `--profile bedoux-admin` in pinned region `ca-central-1`,
  confirmed no EKS clusters, ALBs, target groups, RDS instances, available/pending NAT
  gateways, associated EIPs, unattached EBS volumes, tagged project VPCs, or relevant
  CloudFormation stacks. The broad project-tag sweep returned only the allowlisted ECR
  repositories `bedoux-api` and `bedoux-web`. The USD 20 budget is live with current
  actual spend USD 0.35. `git diff --check` passed. The direct commands underlying
  `make docs-check` passed (`docs-check OK`); the host wrapper could not launch its
  toolbox because Podman cannot set the required sticky bit on `/run/user/1000/libpod`
  in this read-only environment.
- **AWS:** none created or destroyed this session. Estimated session cost: USD 0.
- **Decisions:** none. The P6/P7 S3 image-adapter boundary remains the only open
  owner-approved decision; ADR 0006 and the P5 kill switch/request bounds remain done.
- **Next action:** owner approves the P5 gate in a separate gate commit; then activate
  P6 and begin only P6.1 (Terraform modules + reviewed plan), with NAT disabled from the
  start in the Terraform VPC design.
- **Blocker:** owner approval of the P5 gate; no technical blocker found.

### 2026-07-29 — P5 gate approved; P6 activated — Codex (owner: Tsogo)

- **Phase/task:** Owner explicitly approved the P5 gate and activated P6. P6.1 is now
  the only in-progress checklist item; no P6 implementation has started in this entry.
- **Changed:** overall checkpoint state and phase checklist updated in this file;
  `START-HERE.md` refreshed to point at P6.1.
- **AWS:** none. No resources created or modified. Estimated session cost: USD 0.
- **Decisions:** none new. The P6/P7 S3 image-adapter boundary remains open and must
  be recorded before its implementation phase; the Terraform VPC must disable NAT from
  the start, carrying forward P5.5's finding.
- **Next action:** P6.1 — create Terraform modules and produce a reviewed cold plan;
  do not apply AWS changes until the plan is reviewed and a separate AWS session is
  opened using the manual `docs/runbooks/aws-session.md` checklist.

### 2026-07-29 — P6.1 complete: Terraform modules and cold plan — Codex

- **Phase/task:** P6.1 complete. Terraform now represents the P5 learning profile:
  public-only VPC, no NAT, EKS control plane, one Spot `t3.medium` managed node,
  ECR repositories with lifecycle policies, cluster/node IAM roles, EKS OIDC,
  EBS CSI IRSA/add-on, and ALB Controller IRSA permissions.
- **Changed:** added `infra/terraform/` with pinned Terraform/provider versions,
  root configuration, and modules for VPC, cluster IAM, EKS, workload IAM, EKS
  add-ons, and ECR; refreshed `START-HERE.md` and this progress state.
- **Verified:** `terraform init -backend=false -input=false` succeeded with AWS
  provider `5.100.0` and TLS provider `4.1.0`; `terraform fmt -check -recursive`
  passed; `terraform validate` passed; a no-refresh plan saved outside the repo
  completed with **26 to add, 0 to change, 0 to destroy**. Focused plan/source
  inspection found no `aws_nat_gateway`, NAT EIP, or NAT route resources. The plan
  was local and no-apply.
- **AWS:** none created, modified, or destroyed. Estimated session cost: USD 0.
- **Decisions:** no architecture decision changed. The EBS CSI add-on version is
  an explicit P6.2 input because AWS compatibility is version-specific; P6.2 must
  select and record an exact compatible version before apply. Persistent P5 ECR
  repositories and IAM roles must be imported before apply rather than duplicated.
- **Next action:** P6.2 — manually walk `docs/runbooks/aws-session.md` before any
  apply, import the persistent resources, then run the apply/verify/destroy cycle
  and the full teardown sweep.

### 2026-07-28 — P5.5 complete: full teardown, one real finding fixed — Claude Code (operator: Tsogo)

- **Phase/task:** P5.5, closing out the entire P5 phase.
- **Teardown order** (deliberately sequenced so the ALB controller could
  clean up its own AWS resources before the cluster disappeared):
  1. `helm uninstall bedoux -n bedoux` — deleting the Ingress triggered the
     controller to deregister targets, delete the ALB, delete the target
     group, and delete its managed security group. Confirmed via the
     controller's own logs (`deleting loadBalancer` → `deleted loadBalancer`)
     and cross-checked with `aws elbv2 describe-load-balancers` (empty) and
     `aws ec2 describe-security-groups` (`InvalidGroup.NotFound`) — a real
     `DependencyViolation` retry (ENI detachment lag) resolved on its own
     within about a minute, a known AWS timing gotcha, not a bug.
  2. `helm uninstall aws-load-balancer-controller -n kube-system`,
     `kubectl delete namespace bedoux` — confirmed the `postgres-data` PVC's
     backing `gp3` EBS volume was released automatically (`aws ec2
     describe-volumes` on the PVC tag returned empty), same reclaim-on-delete
     behavior proven in P5.1's scratch test, now proven against the real
     app's volume too.
  3. `eksctl delete cluster --wait` — **failed once** with `Cannot delete
     because cluster bedoux currently has an update in progress` (CFN
     `DELETE_FAILED` on the `ControlPlane` resource). Diagnosed: `aws eks
     describe-cluster` showed `ACTIVE` with no pending updates — a transient
     race with in-flight managed-addon deletion, not a real block. Retried
     `eksctl delete cluster --wait` once more; succeeded cleanly ("all
     cluster resources were deleted").
- **Full `/aws-teardown-verify` sweep, all read-only**: `aws eks
  list-clusters` (empty), ALB/target-group check (empty), `aws rds
  describe-db-instances` (empty), NAT gateways in available/pending state
  (empty), EIPs (empty), unattached EBS volumes (empty), CloudFormation
  stacks in CREATE_COMPLETE/UPDATE_COMPLETE/DELETE_FAILED (empty), VPCs
  tagged `project=bedoux-commerce-cloud` (empty).
- **Real finding — undisclosed NAT Gateway, now fixed**: the
  `resourcegroupstaggingapi get-resources` sweep (by design, a broader net
  than the individual describe-* calls) initially returned 4 entries: an EC2
  instance, an EBS volume, an ENI, and **a NAT Gateway** — none of which the
  individual sweeps above had caught, because that API's tag index lags
  real deletions. Investigated each directly rather than assuming staleness
  (per `AGENTS.md`: "any resource that cannot be explained → refuse and
  record it as a blocker"): the instance was `terminated`, the volume and
  ENI were `NotFound`, and the NAT Gateway's own record showed
  `State: "deleted"` — all four genuinely gone, confirming the tagging API
  was just slow to reflect it, not a real leftover.
  **But the NAT Gateway's existence itself was real** — `CreateTime` matched
  cluster-creation time almost exactly. `k8s/eksctl-cluster.yaml` never set
  `vpc.nat.gateway: Disable`, so `eksctl`'s default VPC template silently
  provisioned one for the entire session — a direct, undetected violation of
  `AGENTS.md`/`docs/cost-guardrails.md`'s explicit "No NAT Gateway in the
  learning profile" rule. Cost impact was trivial (~USD 0.07 for the
  session), but the rule was broken without anyone noticing until this
  teardown sweep caught it. Fixed for future sessions: added `vpc: {nat:
  {gateway: Disable}}` to `k8s/eksctl-cluster.yaml`, validated with `eksctl
  create cluster --dry-run` (confirms the field is accepted, without
  creating anything). Managed node groups default to public subnets
  (`privateNetworking: false`), so nodes don't need NAT for egress — no
  functional tradeoff.
- **Persisted per `docs/cost-guardrails.md`'s allowlist** (no hourly
  charge, deliberately kept rather than deleted): ECR repos `bedoux-api`/
  `bedoux-web`, IAM roles `bedoux-eks-cluster-role`/
  `bedoux-eks-nodegroup-role`/`bedoux-ebs-csi-role`/
  `bedoux-alb-controller-role`, IAM policy `bedoux-alb-controller-policy`,
  `bedoux-iam-scoped` (permanently, per ADR 0007). This corrects the P5.1
  session-log entry's "delete the IAM roles" note from earlier in the
  session — the allowlist explicitly permits keeping them, and doing so
  avoids redoing the ADR 0007/0008-adjacent role setup next P5-family
  session.
- **AWS:** full P5 session total — EKS control plane + 1 Spot `t3.medium`
  node + 1 ALB + 1 NAT Gateway (~2.5hr, the NAT Gateway being the
  undisclosed finding above), all now destroyed. Estimated total session
  cost: well under USD 2, well under the USD 16 stop threshold.
  `aws budgets describe-budgets` still showed USD 0 immediately after
  teardown — expected, billing data lags real-time usage (the same caveat
  documented during P4.4).
- **Decisions:** none new (the NAT Gateway fix is a config correction, not a
  new architecture decision — it enforces an already-existing rule).
- **This closes out the entire P5 phase.** All of P5.1–P5.5 complete with
  evidence above.
- **Next action:** owner approves the P5 gate; then **P6 — Terraform, then
  CI/CD** — Terraform recreates everything P5 built as code (this time
  including `vpc.nat.gateway: Disable`'s Terraform equivalent from the
  start), then GitHub Actions with OIDC.

### 2026-07-28 — P5.4 complete: request trace + break/fix drill against the real ALB — Claude Code (operator: Tsogo)

- **Phase/task:** P5.4, continuing the same session.
- **Trace (T-402)**: cross-referenced the ALB target group's registered
  target IP (`aws elbv2 describe-target-health`) against the `web` pod's
  actual IP (`kubectl get pods -o wide`) — exact match, confirming ALB `ip`
  target mode really does address the pod directly (no kube-proxy hop).
  Then sent a request with a unique marker
  (`GET /api/health?trace=trace-<timestamp>`) and found the same marker in
  both `kubectl logs deploy/web` (arriving from the ALB) and
  `kubectl logs deploy/api` (arriving from the web pod's IP, `/api` prefix
  already stripped) — a real, correlated two-hop trace proving ADR 0008's
  request path (ALB → web → api) end-to-end, not just asserted.
- **Break/fix drill (T-403)**: `kubectl scale deployment/web -n bedoux
  --replicas=0`. Within one poll interval: ALB target state → `draining`,
  `curl` → `503`. **Diagnosed purely from `kubectl`/AWS CLI output**, same
  discipline as P3.5's kind drill: `kubectl get deployment web` showed
  `0/0`, `kubectl get endpoints web` showed `<none>`,
  `aws elbv2 describe-target-health` showed
  `Target.DeregistrationInProgress` — root cause (zero replicas → empty
  Endpoints → ALB has nothing to route to) was unambiguous from the output
  alone. **Fix**: `kubectl scale deployment/web --replicas=1`,
  `kubectl rollout status` confirmed the rollout, then polled target health
  + `curl` until both recovered (`healthy` / `200`) — full recovery
  confirmed, not assumed.
- **AWS:** no new resources; same live set as P5.3. Estimated cost so far:
  well under USD 2 (~2.5hr elapsed).
- **Decisions:** none new.
- **Next action:** P5.5 — full teardown: `helm uninstall bedoux -n bedoux`,
  `eksctl delete cluster --name bedoux --region ca-central-1` (removes the
  node group, VPC, and the ALB via the controller's finalizer — verify the
  ALB is actually gone, not just the Ingress object), delete the
  session-created IAM resources (`bedoux-eks-cluster-role`,
  `bedoux-eks-nodegroup-role`, `bedoux-ebs-csi-role`,
  `bedoux-alb-controller-role`, `bedoux-alb-controller-policy` — `NOT`
  `bedoux-iam-scoped`, which stays permanently per ADR 0007), then
  `/aws-teardown-verify`'s full read-only sweep to confirm the account is
  back to empty.

### 2026-07-28 — P5.3 complete: real ALB, golden-path order proven over public DNS — Claude Code (operator: Tsogo)

- **Phase/task:** P5.3, continuing the same session.
- **ALB Load Balancer Controller installed via Helm** (`eks/aws-load-balancer-controller`
  chart, `kube-system`), backed by its own IRSA role
  `bedoux-alb-controller-role` (federated trust to the cluster's OIDC provider,
  `sub: system:serviceaccount:kube-system:aws-load-balancer-controller`) and a
  new customer-managed policy `bedoux-alb-controller-policy` (the standard
  upstream `iam_policy.json` from the `aws-load-balancer-controller` project,
  downloaded and applied as-is). Both controller pods came up `Running`
  on the first attempt — the IRSA chain worked correctly first try, unlike
  the EBS CSI role which needed the ADR 0007 fixes first (those fixes cover
  the account-wide OIDC/nodegroup gaps, so this role only needed its own
  narrow policy).
- **Real finding — ADR 0008**: the chart's existing `Ingress` template assumed
  the same `nginx.ingress.kubernetes.io/rewrite-target` shape would work for
  ALB. It doesn't — ALB has no path-rewrite annotation. Fixed by branching
  `charts/bedoux/templates/ingress.yaml` on a new `ingress.controller` value:
  the AWS profile now emits a single ALB `Ingress` routing everything to
  `web`, and `/api` prefix-stripping happens via the `web` container's own
  nginx reverse proxy (`apps/web/nginx.conf.template` — logic that already
  existed for Compose, P2.4, and had simply never been exercised in a
  Kubernetes deployment before this). `docs/architecture.md`'s request path
  corrected to match. Full detail:
  `docs/decisions/0008-alb-no-rewrite-web-proxies-api.md`.
  `helm lint` clean; `helm template` confirmed both profiles render the
  correct shape (kind: 2 nginx Ingresses; AWS: 1 ALB Ingress).
- **Deployed for real**: `helm upgrade --install bedoux charts/bedoux -f
  values.yaml -f values-aws.yaml --set api.image.repository=<ecr>/bedoux-api
  --set api.image.tag=p5 --set web.image.repository=<ecr>/bedoux-web --set
  web.image.tag=p5` in the `bedoux` namespace. All pods `Running`/`Completed`
  on the first attempt (api, web, postgres, migration Job); `postgres-data`
  PVC bound against the chart's own `gp3` StorageClass (not the P5.1 scratch
  test — this is the real app's volume).
- **Reachability proven, not assumed**: ALB DNS name
  (`k8s-bedoux-*.ca-central-1.elb.amazonaws.com`) went from `provisioning` to
  serving `HTTP 200` within a few minutes (`aws elbv2 describe-load-balancers`
  + polling `curl`, via a Monitor loop). `/api/health` returned
  `{"status":"ok","orders_enabled":false}` — kill switch correctly off by
  default on the real public endpoint, exactly as ADR-pending-decision #4
  requires before anything is reachable via the ALB DNS name.
- **Golden path proven end-to-end over the real ALB**: seeded once
  (`--set seed.enabled=true`, then back to `false`), a **real Chrome browser
  via Playwright MCP** loaded the live catalog page at the ALB DNS name and
  showed all 6 seeded products (T-401 evidence). Browser click automation hit
  transient timeouts on this run (environmental — the same UI flow was
  already proven working live via Playwright during the P5 pre-work kill-switch
  drill), so the order step was verified via a direct `curl -X POST
  /api/orders` instead: `201`, order confirmed by `id` in the real Postgres
  pod via `kubectl exec ... psql` (`status: submitted`, correct
  `total_cents`). Kill switch flipped back to `false` afterward and confirmed
  via `/api/health` + a `kubectl rollout status` wait — the safe default is
  restored.
- **AWS resources now live**: adds the ALB Load Balancer Controller + its
  IRSA role/policy, 1 real ALB, and the full app (api/web/postgres
  Deployments + Services, migration/seed Jobs, `gp3` PVC) to P5.1/P5.2's
  running total. Estimated cost so far: well under USD 2 (~2hr elapsed:
  control plane + 1 Spot t3.medium + 1 ALB, well under the USD 16 stop
  threshold).
- **Decisions:** ADR 0008 accepted.
- **Next action:** P5.4 — trace a request ALB→pod (CloudWatch/`kubectl logs`
  or similar), then one deliberate breakage diagnosed and fixed, per
  `docs/IMPLEMENTATION-PLAN.md`'s P5 gate (T-402/T-403).

### 2026-07-28 — P5.2 complete: ECR repos + real image push — Claude Code (operator: Tsogo)

- **Phase/task:** P5.2, continuing the same session.
- **ECR repos created**: `bedoux-api`, `bedoux-web` (`ca-central-1`,
  `scanOnPush=true`, `project=bedoux-commerce-cloud`/`environment=learning`
  tags).
- **Images pushed**: `podman login` via `aws ecr get-login-password`, tagged
  the same `p5` images used in P5's live kind verification
  (`localhost/bedoux-api:p5`, `localhost/bedoux-web:p5` — built during the
  kill-switch drill, no rebuild needed) to the ECR registry, pushed both.
  `aws ecr describe-images` confirms both present (`bedoux-api` 72MB,
  `bedoux-web` 27MB, tag `p5`, `imageStatus: ACTIVE`).
- **Scan-on-push status**: not yet populated by `aws ecr describe-images`
  after ~1 minute of polling (`imageScanStatus` field absent) — not treated as
  a blocker; local Trivy scan evidence from P2.5 already covers these image
  contents, and ECR's own scan can complete asynchronously later without
  gating P5.3.
- **AWS:** ECR repos + 2 images added to the live-resources list above. No
  additional ongoing cost (ECR storage for two small images is negligible
  against the USD 16 stop threshold).
- **Decisions:** none new.
- **Next action:** P5.3 — install the AWS Load Balancer Controller via Helm
  (needs its own IRSA role, `bedoux-*`-named, same pattern as the EBS CSI
  role), then `helm upgrade --install bedoux charts/bedoux -f
  charts/bedoux/values.yaml -f charts/bedoux/values-aws.yaml --set
  api.image.repository=<ecr>/bedoux-api --set api.image.tag=p5 --set
  web.image.repository=<ecr>/bedoux-web --set web.image.tag=p5`, verify
  reachability via the ALB's DNS name.

### 2026-07-28 — P5.1 complete: node group, OIDC, EBS CSI driver, gp3 proven live — Claude Code (operator: Tsogo)

- **Phase/task:** P5.1, continuing after ADR 0007's IAM fix (previous entry).
- **`eksctl create nodegroup` retried and succeeded**: `bedoux-ng-spot` (1
  Spot `t3.medium`, `AmazonLinux2023`) came up, `kubectl get nodes` showed it
  `Ready`.
- **OIDC provider association** (`eksctl utils associate-iam-oidc-provider
  --approve`) failed once more on `iam:TagOpenIDConnectProvider` (modern
  `CreateOpenIDConnectProvider` tags inline in one call — `bedoux-iam-scoped`
  v2 only had `Get`/`Create`, not `Tag`). Confirmed the failed call created no
  orphaned provider (`aws iam get-open-id-connect-provider` → `NoSuchEntity`).
  Owner applied a third console edit (`bedoux-iam-scoped` v3): added
  `iam:TagOpenIDConnectProvider` and `iam:DeleteOpenIDConnectProvider` (the
  latter pre-emptively, for P5.5's teardown) to the existing OIDC-provider
  resource scope — no new escalation surface, same pattern as ADR 0007.
  Retried, succeeded.
- **EBS CSI driver IRSA + add-on**: created `bedoux-ebs-csi-role` (federated
  trust to the cluster's OIDC provider, `sub:
  system:serviceaccount:kube-system:ebs-csi-controller-sa`,
  `AmazonEBSCSIDriverPolicy` attached), then `aws eks create-addon
  --addon-name aws-ebs-csi-driver --service-account-role-arn
  <bedoux-ebs-csi-role>` → `ACTIVE`; `ebs-csi-controller`/`ebs-csi-node` pods
  `Running` in `kube-system`.
- **ADR 0006 live-verified, not just chart-rendered**: applied a scratch
  `StorageClass gp3` (`ebs.csi.aws.com`) + PVC + pod (kept separate from the
  real `charts/bedoux` chart, since P5.2/P5.3 haven't pushed real ECR images
  yet). PVC went `Bound`, pod went `Running`, wrote a file to the mounted
  volume and read it back. Cross-confirmed with `aws ec2 describe-volumes`
  (filtered by `kubernetes.io/created-for/pvc/name`): a real 1Gi `gp3` volume,
  `in-use`. Deleted the scratch StorageClass/PVC/pod afterward — confirmed
  `kubectl get pv` empty and the EBS volume gone (CSI driver's own
  delete-on-reclaim, not manual EC2 cleanup).
- **AWS resources now live**: EKS cluster `bedoux` (control plane + 1 Spot
  `t3.medium` node), OIDC provider, EBS CSI driver add-on, IAM roles
  `bedoux-eks-cluster-role`/`bedoux-eks-nodegroup-role`/`bedoux-ebs-csi-role`
  — all tagged `project=bedoux-commerce-cloud`/`environment=learning`.
  Estimated cost so far: well under USD 1 (~1hr elapsed: control plane
  ~USD 0.10/hr + 1 Spot t3.medium, no ALB/RDS/NAT yet).
- **Decisions:** none new beyond ADR 0007's v3 amendment (already covered by
  that ADR's scope — a follow-up narrow grant, not a new design decision).
- **Next action:** P5.2 — create ECR repos, push real `bedoux-api`/`bedoux-web`
  images, then P5.3 deploys `charts/bedoux` with `-f values-aws.yaml` for real
  (this is when the chart's own `gp3` StorageClass template — not the scratch
  one used here — gets its live proof against the real app).

### 2026-07-28 — P5.1 real EKS creation: cluster up, nodegroup blocked then fixed via ADR 0007 — Claude Code (operator: Tsogo)

- **Phase/task:** P5.1, continuing the session opened 2026-07-27.
- **IAM roles created** (both `bedoux-*`-named, per `bedoux-iam-scoped`'s scoping):
  `bedoux-eks-cluster-role` (trust `eks.amazonaws.com`, `AmazonEKSClusterPolicy`),
  `bedoux-eks-nodegroup-role` (trust `ec2.amazonaws.com`,
  `AmazonEKSWorkerNodePolicy` + `AmazonEKS_CNI_Policy` +
  `AmazonEC2ContainerRegistryReadOnly`). Verified live before use: a probe role
  named `eksctl-*` was correctly denied by the scoped policy, a `bedoux-*`-named
  probe role succeeded and was cleaned up — confirming the naming boundary works
  as documented before spending real cluster-creation time on it.
- **Cluster config:** `k8s/eksctl-cluster.yaml` (new, committed) — uses
  `${AWS_ACCOUNT_ID}` envsubst placeholder, never a literal account ID (resolved
  into a `/tmp` scratch file at apply time, never written to the repo). One
  managed Spot node group (`t3.medium`, desired/min/max 1), `withOIDC` left off
  the initial create deliberately so an OIDC permission problem wouldn't roll
  back the whole cluster — associated separately, see below.
- **`eksctl create cluster` — control plane succeeded**, node group failed:
  CloudFormation reported `AccessDenied` on `iam:GetRole` for the account-wide
  service-linked role `AWSServiceRoleForAmazonEKSNodegroup` (EKS's
  `CreateNodegroup` always checks this, using the caller's own IAM
  permissions). Created the SLR directly (`iam:CreateServiceLinkedRole`
  succeeded — not resource-scoped the same way), retried — same denial, proving
  the *check* itself (not just creation) needed `iam:GetRole` on that exact
  resource, which `bedoux-iam-scoped` v1 didn't grant.
- **Second, more serious finding surfaced while diagnosing:** `bedoux-iam-scoped`
  v1 granted `iam:*Policy*` on `arn:aws:iam::*:policy/bedoux-*`, and the policy
  itself is `bedoux-*`-named — so `bedoux-admin` had `iam:CreatePolicyVersion` +
  `iam:SetDefaultPolicyVersion` on its own constraining policy. Confirmed by
  reading the live policy document, not assumed. This is a real
  privilege-escalation path to full account admin, contradicting P4.1's
  documented design intent.
- **Fix — ADR 0007:** owner applied a policy edit via console (root/admin
  identity, deliberately not via `bedoux-admin`'s own API access) adding (a) an
  explicit `Deny` on `CreatePolicyVersion`/`SetDefaultPolicyVersion`/
  `DeletePolicy`/`DeletePolicyVersion` scoped to `bedoux-iam-scoped`'s own ARN,
  and (b) a narrow `Allow` for `iam:GetRole` on exactly the EKS-nodegroup SLR
  ARN. Both verified live as `bedoux-admin`, not assumed: a test
  `create-policy-version` with a wide-open `{"Action":"*","Resource":"*"}`
  document against `bedoux-iam-scoped` returned `AccessDenied ... explicit
  deny`; `aws iam get-role` on the SLR then succeeded where it had previously
  failed. Full detail: `docs/decisions/0007-bedoux-iam-scoped-self-escalation-fix.md`.
- **AWS:** EKS cluster `bedoux` control plane live in `ca-central-1`
  (`project=bedoux-commerce-cloud`, `environment=learning` tags); managed
  node group not yet created (retrying next). Estimated cost so far this
  session: well under USD 1 (control plane ~USD 0.10/hr, no node group running
  yet).
- **Decisions:** ADR 0007 accepted.
- **Next action:** retry `eksctl create nodegroup`, then continue P5.1 (verify
  `kubectl get nodes`), then associate the OIDC provider and proceed to the
  EBS CSI add-on (ADR 0006) before P5.2.

### 2026-07-27 — P5.1 session opened — Claude Code (operator: Tsogo)

- **Phase/task:** P5.1 session start, `/aws-session-start` checklist run for real
  (not paper-rehearsed, unlike P4.4).
- **Checklist evidence:**
  - `aws sts get-caller-identity --profile bedoux-admin` → confirmed `bedoux-admin`
    IAM user, not root.
  - Region confirmed pinned `ca-central-1` (Known facts above), not inferred.
  - `aws budgets describe-budgets` → USD 20 budget, USD 0 actual spend.
  - `aws ce get-cost-and-usage` (current month) → USD 0, `Estimated: true`. Cost
    Explorer is now populated (the ~24h ingestion window from P4.4 has long since
    passed) — first time this command has returned real data in this project.
  - Full leftover sweep, all read-only, all empty: `aws eks list-clusters`,
    `aws elbv2 describe-load-balancers`, `aws rds describe-db-instances`,
    `aws ec2 describe-nat-gateways` (state available/pending),
    `aws ec2 describe-addresses`, `aws ec2 describe-volumes` (status available),
    `aws cloudformation list-stacks` (CREATE_COMPLETE/UPDATE_COMPLETE),
    `aws resourcegroupstaggingapi get-resources` (project=bedoux-commerce-cloud
    tag). No unexplained resources; no stop condition triggered.
- **Session goal:** P5.1 — `eksctl create cluster` (+ EBS CSI add-on/IRSA per
  ADR 0006), continuing through P5.2–P5.5 same-day. Planned end: same day,
  teardown via P5.5 once the trace/break-fix drill (P5.4) is done.
- **AWS:** none created yet by this entry — cluster creation follows immediately.
  Estimated session cost: USD 2–4 (full P5 session, per
  `docs/IMPLEMENTATION-PLAN.md`'s phase table).
- **Next action:** run `eksctl create cluster` for real, record evidence.

### 2026-07-23 — P5 pre-work: gp3/Spot decision + order kill switch, live-verified — Claude Code (operator: Tsogo)

- **Phase/task:** Implemented both pending decisions required before P5.1's eksctl
  cluster (`docs/IMPLEMENTATION-PLAN.md` pending-decisions #3 and #4).
- **Changed:**
  - `docs/decisions/0006-spot-node-gp3-pvc.md` (new ADR) + `docs/decisions/README.md`
    index.
  - `charts/bedoux/templates/storageclass.yaml` (new, gated `storageClass.create`),
    `charts/bedoux/templates/postgres.yaml` (PVC `storageClassName` now
    conditional), `charts/bedoux/values.yaml` (`postgres.storageClassName: ""`,
    `storageClass.create: false`, `api.ordersEnabled: true` defaults),
    `charts/bedoux/values-aws.yaml` (new overlay: `storageClass.create: true`,
    `postgres.storageClassName: gp3`, `api.ordersEnabled: false`).
  - `apps/api/app/config.py` (`orders_enabled`, `max_request_body_bytes` settings),
    `apps/api/app/schemas.py` (`OrderCreate.items` max_length=20),
    `apps/api/app/routers/orders.py` (503 when disabled, checked before any DB
    query), `apps/api/app/main.py` (body-size-limit middleware, `/health` now
    reports `orders_enabled`), `charts/bedoux/templates/api.yaml`
    (`BEDOUX_ORDERS_ENABLED` env from `api.ordersEnabled`).
  - `apps/web/src/api/types.ts` (`HealthStatus`), `apps/web/src/api/client.ts`
    (`getHealth`), `apps/web/src/pages/CartPage.tsx` (fetches health on mount,
    shows a deliberate "Ordering is temporarily disabled" banner and disables the
    submit button — never a raw 403/500).
  - `apps/api/tests/test_health.py` (updated for the new health shape),
    `apps/api/tests/test_order_kill_switch_and_bounds.py` (new: 4 unit tests, no DB
    needed since the kill-switch check runs before any query).
- **Verified, not assumed:**
  - `helm lint charts/bedoux` clean; `helm template ... -f values-aws.yaml` confirmed
    the `gp3` StorageClass renders, the PVC gets `storageClassName: gp3`, and
    `BEDOUX_ORDERS_ENABLED=false` lands in the api Deployment — while the plain
    `values.yaml` path (kind) renders zero StorageClass resources and
    `ORDERS_ENABLED=true`.
  - `pytest -v` (apps/api, local venv): 6/6 non-DB tests pass, including the 4 new
    ones (503 on disabled, `/health` reflects state, 21-line order rejected 422,
    oversized body rejected 413).
  - `npm test` + `npm run build` (apps/web): 9/9 tests pass, clean `tsc -b` + `vite
    build`.
  - **Live against the real kind cluster** (rebuilt `bedoux-api:p5` /
    `bedoux-web:p5` images, `podman save` + `kind load image-archive`, `helm
    upgrade --reuse-values`): with `api.ordersEnabled=false`, `curl
    /api/orders` returned `503 {"detail":"ordering is currently disabled"}` (not a
    crash) and `/api/health` correctly reported `orders_enabled: false`; a **real
    Chrome browser via Playwright MCP** showed the cart page's disabled banner and
    a disabled "Submit order" button. Flipped back to `ordersEnabled=true`: banner
    disappeared, button re-enabled, and a full golden-path order (add mug to cart →
    submit → confirmation page) completed successfully — confirming the kill
    switch doesn't break the normal path. Postgres's existing PVC
    (`storageClassName: standard`, kind's default) and its data survived the whole
    upgrade cycle untouched, confirming the chart change is backward-compatible.
  - `make docs-check` passes.
- **AWS:** none. Estimated session cost: USD 0. (Real EBS CSI/gp3 proof against a
  live add-on happens in P5.1, since no EKS cluster exists yet — kind has no
  `ebs.csi.aws.com` provisioner to test against.)
- **Decisions:** ADR 0006 accepted. ALB inbound CIDR restriction (the remaining
  piece of pending-decision #4) is deferred to P5.3, since it needs a real ALB
  security group to attach to — noted here so it isn't forgotten.
- **Next action:** P5.1 — run `/aws-session-start`, then `eksctl create cluster`
  (with the EBS CSI add-on + its IRSA role) for real.

### 2026-07-23 — P4 gate approved, P5 activated — Claude Code (operator: Tsogo)

- **Phase/task:** Owner approved the P4 gate ("lets move on P5 and approve the gate").
  No new evidence generated by this entry itself — see the P4.4 entry below for the
  gate's supporting evidence.
- **Changed:** `docs/PROGRESS.md` overall status table (active phase → P5, active task →
  P5.1) and the P4 gate line in the phase checklist.
- **AWS:** none. Estimated session cost: USD 0.
- **Decisions:** none new.
- **Next action:** P5.1 — run `/aws-session-start`, then `eksctl create cluster`. Per
  `docs/IMPLEMENTATION-PLAN.md`'s pending-decisions #3 and #4, the gp3 PVC/EBS CSI design
  and the order-write kill switch + request bounds must be implemented as part of P5
  (kill switch off by default before anything is reachable via the public ALB DNS name).

### 2026-07-23 — P4.4 session runbook rehearsal, P4 closed — Claude Code (operator: Tsogo)

- **Phase/task:** P4.4 complete, **closes out the entire P4 phase** (see phase-checklist
  entry above for full evidence).
- **Changed:** `docs/runbooks/aws-session.md` (added a Cost Explorer data-availability
  caveat), `docs/HANDOFF.md` (fully regenerated — see finding below).
- **AWS:** zero resources created. Ran every read-only command from
  `/aws-session-start` and `/aws-teardown-verify` for real against the actual account
  (`--profile bedoux-admin`, `ca-central-1`) — full leftover-resource sweep came back
  completely empty, and the identity/budget checks both confirmed correctly. Estimated
  session cost: USD 0.
- **Two real findings, both fixed, not just noted:**
  1. Cost Explorer (`aws ce get-cost-and-usage`) isn't ready for ~24h on a brand-new
     account — added a caveat to the runbook so this doesn't read as a failure next
     time; the Budgets check is unaffected and is the more reliable pre-session
     signal anyway.
  2. `docs/HANDOFF.md` hadn't been regenerated since 2026-07-18 — every session since
     (P2, P3, P4.1–4.3) skipped that closeout step. This means a cold-start agent
     session that trusted `HANDOFF.md` over `docs/PROGRESS.md` would have picked up
     badly stale context. Regenerated it now with accurate state through P4.4 and an
     explicit pointer to the pending-decisions section so this doesn't repeat.
- **Decisions:** none new.
- **Next action:** owner approves the P4 gate; then **P5 — Manual EKS session**, the
  first phase that creates real billable AWS resources (~$2–4, same-day teardown).
  Before P5.1: re-read `docs/IMPLEMENTATION-PLAN.md`'s pending-decisions #3 and #4
  (Spot-node risk + gp3 PVC via EBS CSI; order-write kill switch + request bounds) —
  both must actually be implemented in P5, not just remembered.
- **Blockers:** none.

### 2026-07-23 — P4.2 budget + Cost Anomaly Detection — Claude Code (operator: Tsogo)

- **Phase/task:** P4.2 complete (see phase-checklist entry above for full evidence).
- **Changed:** no repo files — this was an owner-executed AWS console task.
- **AWS:** USD 20 monthly cost budget created (AWS Budgets' standard template, 80%/100%
  alert thresholds); Cost Anomaly Detection monitor + alert subscription added. No
  billable resources created — estimated session cost USD 0.
- **Decision:** accepted the AWS default template's two thresholds (80%/100% = USD
  16/20) instead of the four-threshold 5/10/16/20 plan originally sketched in
  `docs/IMPLEMENTATION-PLAN.md`. Reasoning recorded in the phase-checklist entry above
  — the two highest-value tripwires are still covered, sessions are short/same-day
  teardown by design, and Cost Anomaly Detection is a second independent safety net.
- **Next action:** P4.4 — paper rehearsal of the session runbook (dry-run
  `docs/runbooks/aws-session.md` end-to-end without creating any AWS resources).
- **Blockers:** none.

### 2026-07-23 — P4.1 + P4.3 root MFA, non-root identity, region pin — Claude Code (operator: Tsogo)

- **Phase/task:** P4.1 and P4.3 complete (see phase-checklist entries above for full
  evidence).
- **Changed:** `docs/local-tooling.md` (new "AWS CLI identity" section — the
  `bedoux-admin` profile convention, why `PowerUserAccess` + a scoped custom IAM policy
  instead of `AdministratorAccess`, the `bedoux-*` naming requirement),
  `docs/runbooks/aws-session.md` (Before-the-session checklist now checks for the
  `bedoux-admin` identity specifically, not just "an" identity).
- **AWS:** account created (Proton Mail signup, paid plan chosen over the 6-month free
  plan — reasoning: this project's own budget/session guardrails are stronger than
  AWS's auto-close safety net, and a mid-project forced account closure would be
  actively disruptive). Root MFA enabled; root has zero access keys. IAM user
  `bedoux-admin` created with MFA (passkey). No billable resources created — estimated
  session cost USD 0.
- **Decisions:**
  - Region **`ca-central-1`** (owner choice — closer to America/Edmonton than the
    more commonly-tutorialed `us-east-1`).
  - Declined AWS's bundled "Agent Toolkit for AWS" auto-setup script (offered during
    account signup). It would have reinstalled the AWS CLI over the P1.1-pinned
    version, auto-edited `AGENTS.md`/`CLAUDE.md` with its own rules, and added an AWS
    MCP server + skills of unreviewed scope. Read the actual setup script via WebFetch
    before deciding — it does real system changes (`curl | bash`, config file edits)
    that shouldn't be run unread. Took only the useful part (the `aws login`
    browser-SSO auth pattern, which produces temporary sessions, not long-lived
    access keys) and ran it manually instead.
  - IAM design: `bedoux-admin` gets `PowerUserAccess` (AWS managed — covers every
    service this project touches, excludes IAM/Organizations) plus a small custom
    policy scoped to IAM role/policy/OIDC-provider actions on `bedoux-*`-named
    resources only — the minimum `eksctl`/IRSA need to create their own roles, without
    general IAM management. Chosen over blanket `AdministratorAccess` specifically to
    avoid a privilege-escalation-capable identity, and framed as a deliberate
    portfolio decision given this project's EKS/platform-engineering priority. Every
    IAM role/policy this project creates from here on must be named `bedoux-*` for
    this to keep working.
- **Verification:** root session first (`aws login` as root, confirmed via
  `sts get-caller-identity` showing `:root` — correctly flagged as *not* the intended
  working identity, not accepted as gate evidence); then `bedoux-admin` created and
  verified via `aws sts get-caller-identity --profile bedoux-admin` showing
  `arn:aws:iam::<redacted>:user/bedoux-admin`. Account ID never recorded in this repo
  at any point (owner flagged twice for pasting it unredacted in chat; not committed
  anywhere).
- **Next action:** P4.2 — budget + alerts + Cost Anomaly Detection (owner console
  checklist: USD 20 budget with 5/10/16/20 alerts).
- **Blockers:** none.

### 2026-07-19 — P3.5 drills — Claude Code (operator: Tsogo)

- **Phase/task:** P3.5 complete, **closes out the entire P3 phase** (see phase-checklist
  entry above for full per-drill evidence: scale, pod deletion, broken config diagnosed
  from `kubectl` output alone, rollback).
- **Changed:** no chart/manifest changes — this was pure operational verification
  against `charts/bedoux/` as built in P3.4.
- **AWS:** none. Estimated session cost: USD 0.
- **Two real findings recorded, not just the planned drill outcomes:**
  1. Fixing a drifted ConfigMap via `helm upgrade` doesn't restart pods already
     running against the old value — needs an explicit `kubectl rollout restart`
     (or a checksum-annotation pattern this chart doesn't have yet).
  2. Plain `helm upgrade` with no flags silently reuses the *previous* release's
     user-supplied values rather than falling back to `values.yaml` defaults —
     `--reset-values` is what's actually required. Verified precisely with `helm get
     values` before/after.
- **Next action:** P3 gate is ready for owner approval. Once approved, P4 — AWS account
  readiness (root MFA, budget/alerts, region pin, session-runbook dry run) — all
  console-checklist items for the owner, no AWS resources created yet.
- **Blockers:** none.

### 2026-07-19 — P3.4 Helm chart — Claude Code (operator: Tsogo)

- **Phase/task:** P3.4 complete (see phase-checklist entry above for full evidence).
- **Changed:** `charts/bedoux/` (new): `Chart.yaml`, `values.yaml`,
  `templates/_helpers.tpl`, `templates/postgres.yaml`, `templates/api.yaml`,
  `templates/web.yaml`, `templates/ingress.yaml`, `templates/migration-job.yaml`,
  `templates/seed-job.yaml`. `docs/decisions/0005-helm-migration-hook-job.md` corrected
  in place (hook trigger `pre-install`→`post-install`, with the live evidence for the
  fix) — not superseded, since this is a same-day factual correction caught before any
  chart depended on the wrong version, not a reconsidered tradeoff.
- **AWS:** none. Estimated session cost: USD 0.
- **Bug caught before it ever ran live:** ADR 0005 as originally written specified a
  `pre-install,pre-upgrade` hook. Building the actual migration Job against it and
  testing with a second scratch chart proved `pre-install` hooks fire **before** any of
  the chart's own non-hook resources exist — a Job referencing this chart's
  `postgres-credentials` Secret would fail every fresh install. Fixed to
  `post-install,pre-upgrade`, re-verified with the same scratch-chart method (fires
  after install-time resources exist, still fires before an existing release upgrades,
  still never fires on rollback).
- **Verification, against the real cluster, not just scratch charts:** deleted the
  P3.1–P3.3 plain-manifest resources; fresh `helm install` succeeded (migration hook
  correctly saw its Secret dependency); `helm upgrade --set seed.enabled=true` seeded
  the catalog; full golden path re-verified through Ingress including a real
  `POST /api/orders` cross-checked in Postgres and a pass in the same real Chrome
  browser via Playwright MCP. **Deliberate failure drill:** upgraded with a nonexistent
  `api.image.tag` — the `pre-upgrade` migration hook (which also uses that same image)
  failed with `ErrImagePull`/`DeadlineExceeded`, Helm refused the release
  (`UPGRADE FAILED`), and the running app was never touched — confirmed via `curl`
  returning 200 throughout and `helm history` showing the failed revision recorded
  without disturbing the deployed one. Recovered with a corrected upgrade, then ran a
  real `helm rollback` (revision 4 → 2): a job-list diff confirmed **zero hooks fired**
  during rollback, and all 6 products plus the 1 real order survived untouched.
- **Secondary finding, recorded:** a *failed* hook Job is not auto-cleaned by
  `hook-delete-policy: before-hook-creation` — that policy only triggers relative to a
  successful prior hook of the same name pattern. `bedoux-migrate-3` (the failed one)
  persisted until manually deleted. Worth remembering for P8's troubleshooting
  runbooks.
- **Note:** `k8s/*.yaml` (P3.1–P3.3's plain manifests) are left in place as the
  historical record of that stage — `charts/bedoux/` is the live deployment artifact
  from here forward; P3.5 and beyond use Helm, not `kubectl apply -f k8s/`.
- **Next action:** P3.5 — drills (scale, pod deletion, broken config, rollback). Much
  of the rollback drill's core mechanics were already exercised here as part of
  building the chart; P3.5 should formalize and extend rather than repeat from zero.
- **Blockers:** none.

### 2026-07-19 — ADR 0005: Helm migration hook Job — Claude Code (operator: Tsogo)

- **Phase/task:** required prerequisite for P3.4 (per the pending owner-approved
  decision recorded earlier this session) — the ADR only, not the Helm chart itself,
  which is still NOT STARTED.
- **Changed:** `docs/decisions/0005-helm-migration-hook-job.md` (new), `docs/decisions/
  README.md` (index entry).
- **AWS:** none. Estimated session cost: USD 0.
- **Decision:** migrations run as a `pre-install,pre-upgrade` Helm hook Job
  (`alembic upgrade head` only, `backoffLimit`+`activeDeadlineSeconds` set, kept around
  after success via `hook-delete-policy: before-hook-creation`); no automatic
  `alembic downgrade` on rollback; seed becomes a separate opt-in Job, off by default.
  Full detail and consequences in the ADR.
- **Verification (not just documentation):** built a scratch Helm chart in `/tmp` with
  a `pre-install,pre-upgrade`-hooked Job, ran `helm install` (hook fired, `hook-job-1`),
  `helm upgrade` (hook fired again, `hook-job-2`), then `helm rollback` to revision 1 —
  confirmed via `kubectl get jobs` and `kubectl get events` that **no new hook Job ran
  and no hook-related event appeared** during the rollback; only the Deployment's pods
  reverted. This directly confirms the ADR's central claim instead of assuming it from
  memory of Helm's docs. Scratch chart, namespace, and release fully torn down
  afterward; confirmed the real `bedoux` namespace/app were unaffected throughout
  (catalog still `curl`-reachable, 200, immediately after cleanup).
- **Next action:** P3.4 — build the actual Helm chart from `k8s/` against this ADR's
  design (migration hook Job, seed as an opt-in Job, values for image tags/replicas/
  resources), then `helm lint` clean and a real `helm install`/`upgrade`/`rollback`
  cycle against the live cluster.
- **Blockers:** none.

### 2026-07-19 — P3.3 Ingress routing — Claude Code (operator: Tsogo)

- **Phase/task:** P3.3 complete (see phase-checklist entry above for full evidence).
- **Changed:** `k8s/kind-config.yaml` (ingress-ready node label, port 80/443
  `extraPortMappings`), `k8s/30-web.yaml` (Service NodePort → ClusterIP),
  `k8s/40-ingress.yaml` (new — two `Ingress` objects: `/api` prefix-stripped straight to
  `api`, `/` to `web`).
- **AWS:** none. Estimated session cost: USD 0.
- **Decision:** two separate `Ingress` objects instead of one, since
  `rewrite-target` is an Ingress-wide annotation, not per-path — and the split
  intentionally mirrors production (per `docs/architecture.md`, the ALB already routes
  straight to pod IPs per target group), so this isn't a kind-only workaround; P5's ALB
  Ingress should look the same shape.
- **Verification:** recreated the kind cluster with the new config (kind clusters are
  expected to be recreated for structural changes; data was re-seeded, not an
  accident), installed ingress-nginx pinned to `controller-v1.15.1`, confirmed the
  controller `Ready` and the Ingress resolved to the correct backend via `kubectl
  describe ingress`. Re-ran the full golden path through the Ingress port: catalog,
  `/api/products/{id}` (proves the rewrite handles nested paths, not just the bare
  prefix), and a real `POST /api/orders` (3× tote → `total_cents: 6600`) cross-checked
  directly in Postgres. Re-drove the same real Chrome browser (Playwright MCP) against
  the Ingress URL — catalog rendered correctly.
- **Next action:** P3.4 — convert to a Helm chart (`helm lint` clean). **Before
  starting: read "Pending owner-approved decisions" #1 in `docs/IMPLEMENTATION-PLAN.md`
  and write the required ADR for the migration-hook-Job design first.**
- **Blockers:** none.

### 2026-07-19 — P3.2 probes, limits, config — Claude Code (operator: Tsogo)

- **Phase/task:** P3.2 complete (see phase-checklist entry above for full evidence).
- **Changed:** `k8s/10-postgres.yaml` (`DATABASE_URL` added to the existing Secret,
  `pg_isready` readiness+liveness probes, resource requests/limits), `k8s/20-api.yaml`
  (`wait-for-postgres` init container, `BEDOUX_DATABASE_URL` now via `secretKeyRef`
  instead of a plaintext duplicate, `/health` readiness+liveness probes, resource
  requests/limits), `k8s/30-web.yaml` (new `web-config` ConfigMap for the non-secret
  `API_UPSTREAM`, `/` readiness+liveness probes, resource requests/limits).
- **AWS:** none. Estimated session cost: USD 0.
- **Decision (in-flight correction of the original plan):** the plan said "move DB URL
  into a ConfigMap" — corrected to a Secret instead, since `BEDOUX_DATABASE_URL` embeds
  the Postgres password. ConfigMaps are plaintext-readable by anyone with namespace read
  access; ended up with a clean rule instead: credential-bearing config → Secret,
  everything else → ConfigMap. `API_UPSTREAM` (no credential) is the ConfigMap example.
- **Verification:** `kubectl apply` rolled out clean; confirmed via `kubectl describe
  pod` that all probes/limits/env sources are live as specified. Data survived the
  rollout (PVC untouched). Then ran a real failure drill instead of trusting the YAML:
  scaled `postgres` to 0 replicas and restarted `api` — the new pod sat at `Init:0/1`
  for the whole outage (proof the P3.1 race — a pod starting before postgres finished
  its first-run init — is now architecturally prevented, not just probed around).
  Scaled `postgres` back to 1; the blocked `api` pod's init container completed and the
  pod became `1/1 Ready` the moment postgres was reachable, confirmed with `kubectl
  wait --for=condition=ready`. Re-verified the full catalog through the same hostPort
  chain as P3.1 afterward — 200, 6 products, unaffected by the drill.
- **Next action:** P3.3 — Ingress routing (`/` and `/api` through one entrypoint,
  replacing the P3.1 NodePort stopgap).
- **Blockers:** none.

### 2026-07-19 — P3.1 kind cluster + plain manifests — Claude Code (operator: Tsogo)

- **Phase/task:** P3.1 complete (see phase-checklist entry above for full evidence).
- **Changed:** `k8s/kind-config.yaml` (cluster config + hostPort mapping),
  `k8s/00-namespace.yaml`, `k8s/10-postgres.yaml` (Secret + PVC + Deployment + Service,
  `PGDATA` pinned to a subdirectory of the mount to avoid non-empty-directory initdb
  failures), `k8s/20-api.yaml`, `k8s/30-web.yaml` (Deployment + Service per component;
  web is NodePort 30080 as a stopgap until P3.3's Ingress).
- **AWS:** none. Estimated session cost: USD 0.
- **Bug/gotcha found and worked around:** `kind load docker-image` failed with
  `"not present locally"` against this host's rootless-podman kind provider, even with
  the exact `localhost/<repo>:<tag>` reference `podman images` reports. Worked around
  with `podman save` → `kind load image-archive`, confirmed landed via
  `podman exec bedoux-control-plane crictl images`. Documented in `docs/local-tooling.md`.
- **Decisions:** none new — plain manifests only, no Helm yet (P3.4).
- **Next action:** P3.2 — readiness/liveness probes (the postgres init-race hit during
  this task is exactly what a readiness probe on `api`/`web`, and startup ordering via
  probes rather than `depends_on`, is meant to prevent in Kubernetes), resource
  requests/limits, move DB URL into a ConfigMap.
- **Blockers:** none.

### 2026-07-18 — P2.5 Compose web service, image scan, P2 closed — Claude Code (operator: Tsogo)

- **Phase/task:** P2.5 complete; P2 gate ready for owner approval.
- **Changed:** `apps/web/Dockerfile` (multi-stage, node:24-alpine build → nginx-unprivileged
  runtime, non-root, `apk upgrade` for current patches), `apps/web/nginx.conf.template` +
  `.dockerignore` (proxies `/api/` to `${API_UPSTREAM}` via explicit-variable `envsubst`,
  deliberately outside the base image's auto-templated `/etc/nginx/templates/` to avoid its
  unscoped envsubst mangling nginx's own `$host`/`$uri`), `docker-compose.yml` (`web`
  service + api healthcheck), `apps/api/Dockerfile` (now also copies `migrations/` +
  `alembic.ini` — was missing, so a deployed API container couldn't run its own migrations),
  `apps/api/pyproject.toml` (`fastapi>=0.118,<0.119` → `>=0.139,<0.140`, fixing 3 HIGH CVEs
  in the transitively-pinned `starlette`), `docs/local-tooling.md` (trivy entry + scan
  recipe).
- **AWS:** none. Estimated session cost: USD 0.
- **Commands/tests:** installed trivy 0.72.0 (static binary, host `~/.local/bin`); scanned
  both images via `podman save` + `trivy image --input` (no podman socket active, so the
  direct `trivy image <name>` path doesn't work here — documented). API: 3 HIGH Python
  vulns (starlette) → fixed → 0. Web: 35 HIGH/CRITICAL OS vulns (stale Alpine base) → `apk
  upgrade` in the runtime stage → 0. 22 OS-level findings remain on the API's debian-based
  slim image with no fix available upstream — tracked, not fixed today. Re-ran the full
  9-test API suite after the fastapi bump — still 9/9. Built both final images, ran
  postgres+api+web as three real containers on an isolated podman network, ran
  `alembic upgrade head` and `python -m app.seed` **inside the deployed API container**,
  confirmed both app containers non-root via `podman exec ... id`, then drove the
  published port 8080 with `curl`: catalog (6 products), category filter (2 apparel),
  and a real `POST /api/orders` round-trip through the nginx proxy. Final sizes: API
  206MB, web 62.4MB.
- **Bugs found and fixed during this task:** (1) wrong registry path for the nginx base
  image — `nginxinc/` is a separate namespace, not under `docker.io/library/`; (2)
  `npm ci` failed on lockfile drift crossing glibc (host) → musl (Alpine container) for
  optional native binary packages — switched to `npm install` in the Dockerfile with an
  inline comment explaining why; (3) the API Dockerfile omission described above.
- **Decisions:** none new (fixes above are bug fixes, not architecture changes).
- **Cleanup:** all test containers, the temporary podman network, superseded image tags,
  and scan tarballs removed; confirmed via `podman ps -a` / `network ls` / `images` /
  `volume ls` that only the two pre-existing toolboxes remain.
- **Next action:** owner approves the P2 gate; then P3.1 — kind cluster + plain manifests
  (must start by fixing the rootless-Podman `Delegate=yes` gap noted in
  `docs/local-tooling.md`).
- **Blockers:** none. Carry-forward items for later phases: 22 unfixed OS-level CVEs on
  the API base image (re-scan later, no upstream fix exists yet). kind/rootless-Podman
  fix and the real-browser visual check were both closed out on 2026-07-19 — see entries
  below.

### 2026-07-19 — Browser verification (Playwright MCP + real Chrome) — Claude Code (operator: Tsogo)

- **Phase/task:** closes the P2.4 real-browser gap flagged 2026-07-18 (no
  browser-automation tool was available at that time).
- **Changed:** none in-repo except this record and the `local-tooling.md` kind fix
  below — this was verification, not implementation.
- **Setup:** registered Playwright MCP (`claude mcp add playwright`) scoped locally to
  this project, configured to attach via `--cdp-endpoint` to a real, separately-launched
  **Google Chrome** (Flatpak `com.google.Chrome`, not a bundled Chromium) running with
  `--remote-debugging-port=9222` and a throwaway `--user-data-dir=/tmp/chrome-mcp-profile`
  (never the owner's real Chrome profile). This guarantees only actual Chrome is driven,
  per the owner's explicit requirement.
- **Verification:** built `bedoux-api:verify` and `bedoux-web:verify` fresh from the
  current Dockerfiles; ran postgres+api+web as three podman containers on an isolated
  network (no compose CLI available on this host, same workaround as P2.5); ran
  migrations + seed inside the deployed API container; confirmed `/health` and the
  nginx `/api` proxy both green. Then drove the **actual rendered page** in Chrome via
  Playwright MCP: loaded the catalog (all 6 seeded products visible with correct
  prices/categories/search box), opened the Bedoux Canvas Tote detail page, clicked
  "Add to cart" (cart badge updated 0→1 live, confirmation toast appeared), opened
  `/cart` (correct item/qty/total), clicked "Submit order", landed on the real order
  confirmation page (`status: submitted`, correct line item and total). Cross-checked
  directly in Postgres: `select * from orders` showed the same order id with
  `total_cents: 2200`, matching the $22.00 shown on screen — proving the order is a real
  server-side row, not just client state.
- **Cleanup:** all three verify containers, the temporary network, and both `:verify`
  images removed; confirmed via `podman ps -a` clean.
- **Decisions:** none new.
- **Gap closed:** T-101 (browser happy path) can now be treated as fully verified —
  no longer just DOM-test/curl coverage.
- **Next action:** owner approves the P2 gate; then P3.1.
- **Blockers:** none. Note for future sessions: the debug Chrome instance is a
  background process tied to the shell that launched it — if the agent session or host
  restarts, relaunch with
  `flatpak run com.google.Chrome --remote-debugging-port=9222 --user-data-dir=/tmp/chrome-mcp-profile`
  before Playwright MCP tools will work again.

### 2026-07-18 — P2.4 React frontend — Claude Code (operator: Tsogo)

- **Phase/task:** P2.4 complete.
- **Changed:** scaffolded `apps/web` with `npm create vite@latest -- --template
  react-ts`; added `react-router-dom`, `vitest`, `@testing-library/react`,
  `@testing-library/jest-dom`, `@testing-library/user-event`, `jsdom`. Removed Vite
  template boilerplate (logos, counter demo, template CSS). Built: `src/api/client.ts`
  + `types.ts` (fetch wrapper, `/api` base path), `src/cart/CartContext.tsx`
  (`localStorage`-backed cart with add/remove/setQuantity/clear + derived totals),
  `src/pages/{Catalog,ProductDetail,Cart,OrderConfirmation}Page.tsx`,
  `src/components/Layout.tsx`, wired in `App.tsx`/`main.tsx`. `vite.config.ts` dev
  proxy (`/api` → `VITE_PROXY_TARGET`, default `localhost:8000`) so local dev mirrors
  the Kubernetes Ingress path routing. 6 placeholder product SVGs at
  `public/static/products/` matching `app/seed.py` filenames exactly.
- **AWS:** none. Estimated session cost: USD 0.
- **Commands/tests:** `npm run build` (`tsc -b && vite build`) — caught and fixed a
  real TS6 `erasableSyntaxOnly` rejection of a constructor parameter property in
  `ApiError`, then built clean (240KB bundle, gzip 77KB); `npm test` (vitest) → 9/9
  passed (7 cart unit tests incl. persistence-across-remount; 2 full rendered-DOM
  flow tests via `@testing-library/react` + real `user-event` clicks, `fetch` mocked
  only at the network boundary). Separately booted the **real** API (real Postgres +
  seed data) and the **real** Vite dev server together and drove the dev proxy with
  `curl`: `GET /api/products` (6), category filter (2 apparel), `POST /api/orders`
  (2× mug → `total_cents: 2800`), `GET /api/orders/{id}` confirmation — same network
  path a browser would take. All processes/containers/volumes torn down and
  confirmed clean afterward.
- **Decisions:** none new.
- **Gap noted (flagged to owner, not silently passed over):** no browser-automation
  tool is available here, so nothing was visually confirmed in an actual browser —
  DOM-test + curl coverage is real but not a substitute for eyes-on confirmation.
  Recommend a manual click-through before treating T-101 (browser happy path) as
  fully closed.
- **Next action:** P2.5 — Compose file (add the `web` service to the existing
  `postgres`+`api` `docker-compose.yml`) + image scan + size record.
- **Blockers:** none for P2.4 itself; the browser-verification gap above is worth the
  owner's attention before P2's overall gate.

### 2026-07-18 — P2.3 catalog + order endpoints — Claude Code (operator: Tsogo)

- **Phase/task:** P2.3 complete.
- **Changed:** `apps/api/app/schemas.py` (Pydantic request/response models —
  `OrderItemIn` deliberately has no price field), `apps/api/app/routers/products.py`
  (`GET /products` with category/search/pagination, `GET /products/{id}`),
  `apps/api/app/routers/orders.py` (`POST /orders` — prices always read from the DB,
  never the client; `GET /orders/{id}`), wired into `app/main.py`;
  `apps/api/tests/conftest.py` (real-DB `client` fixture that truncates tables between
  tests) and `apps/api/tests/test_catalog_and_orders.py` (5 integration tests).
  **Fixed a real bug found during this task:** `price_cents`/`total_cents`/
  `unit_price_cents` changed from `Numeric(10,0)` to `Integer` in `app/models.py` and
  in the still-unapplied-anywhere-but-my-test-containers initial migration file
  (edited in place, not amended as a new migration, since P2.2's migration had never
  touched a shared or persistent database).
- **AWS:** none. Estimated session cost: USD 0.
- **Commands/tests:** fresh `postgres:16-alpine` via `podman run`; `alembic upgrade
  head` then confirmed via `psql \d products` that `price_cents` is genuinely
  `integer`; `pytest -v` → 9/9 passed (5 new + the 4 from P2.2); separately booted the
  real `uvicorn` server and drove it with `curl` end-to-end — filtered
  `/products?category=apparel`, placed a real order for 3 mugs
  (`POST /orders` → `total_cents: 4200`, matching 1400×3), and re-fetched the same
  order via `GET /orders/{id}` — byte-identical JSON. Test container, its volume, and
  local `__pycache__` all removed afterward.
- **Decisions:** none new.
- **Next action:** P2.4 — React catalog/detail/cart/confirmation pages.
- **Blockers:** none.

### 2026-07-18 — P2.2 schema, migrations, seed — Claude Code (operator: Tsogo)

- **Phase/task:** P2.2 complete.
- **Changed:** `apps/api/app/models.py` (SQLAlchemy 2.0 `Product`/`Order`/`OrderItem`),
  `apps/api/app/db.py` (engine/session), `apps/api/app/config.py` (pydantic-settings,
  local-dev-only default `DATABASE_URL`), Alembic wiring (`alembic.ini`,
  `migrations/env.py`, `migrations/script.py.mako`, autogenerated initial revision),
  `apps/api/app/seed.py` (idempotent 6-product synthetic catalog),
  `apps/api/tests/test_schema_and_seed.py` (skips without `BEDOUX_DATABASE_URL`), root
  `docker-compose.yml` (postgres + api, healthcheck-gated `depends_on`).
- **AWS:** none. Estimated session cost: USD 0.
- **Commands/tests:** started real `postgres:16-alpine` via `podman run`; `alembic
  upgrade head` → `psql \dt` shows `products`, `orders`, `order_items`,
  `alembic_version`; `python -m app.seed` run twice — 6 inserted then 0 inserted
  (idempotent); `psql SELECT` confirms exactly 6 correct rows; `pytest -v` → 4/4 passed
  with `BEDOUX_DATABASE_URL` set, 2 passed + 2 skipped cleanly without it;
  `docker-compose.yml` parsed and validated with `yaml.safe_load`. Removed the test
  container and its anonymous volume afterward (`podman volume ls` empty of project
  data).
- **Decisions:** none new.
- **Gaps noted (not blocking):** no `docker compose`/`podman-compose` CLI on this host
  and host `python3` has no `pip` module — full `docker compose up` validation deferred
  to P2.5 (which owns extending the Compose file with the frontend anyway).
- **Next action:** P2.3 — catalog + order endpoints + integration tests.
- **Blockers:** none.

### 2026-07-18 — P2.1 FastAPI skeleton — Claude Code (operator: Tsogo)

- **Phase/task:** P1 gate approved (owner: "keep going on P2"); P2.1 complete.
- **Changed:** added `apps/api/` — `pyproject.toml` (fastapi, uvicorn; dev extras
  pytest+httpx), `app/main.py` (`/health` endpoint + OpenAPI metadata),
  `tests/test_health.py` (2 tests), multi-stage `Dockerfile` (python:3.12-slim builder +
  runtime, non-root uid 10001 `bedoux`, `HEALTHCHECK`), `.dockerignore`.
- **AWS:** none. Estimated session cost: USD 0.
- **Commands/tests:** local venv `pytest -v` → 2 passed; `uvicorn` run on
  `127.0.0.1:8123`, real `curl /health` → `{"status":"ok"}` 200, real `curl /docs` → 200;
  `podman build -t bedoux-api:dev .` clean; `podman run` + `podman exec ... id` →
  `uid=10001(bedoux)`; real HTTP round-trip through the container's published port
  confirmed `/health` again; image 163MB; container and image removed after the test
  (no leftover local state).
- **Decisions:** none new.
- **Next action:** P2.2 — PostgreSQL schema, migrations, seed data (still local,
  no AWS).
- **Blockers:** none.

### 2026-07-18 — P1 local toolchain — Claude Code (operator: Tsogo)

- **Phase/task:** P1.1 and P1.2 complete; P1 gate ready for owner approval.
- **Changed:** installed aws-cli 2.36.2, kubectl v1.36.2, eksctl 0.229.0, kind v0.32.0,
  helm v3.21.3, terraform v1.15.8 as static binaries to host `~/.local/bin`; installed
  `make` (GNU Make 4.4.1) + `podman` package into the toolbox `bedoux-aws` via dnf;
  added `~/.local/bin/make` wrapper (`toolbox run -c bedoux-aws /usr/bin/make "$@"`);
  updated `docs/local-tooling.md` with full version/method table and a documented
  rootless-Podman gap for `kind` (needs cgroup `Delegate=yes`) deferred to P3.1.
- **AWS:** none. No AWS account contacted; `aws configure` was never run. Estimated
  session cost: USD 0.
- **Commands/tests (T-011):** `make tools-check` from a plain host shell →
  "All project prerequisites are available."; `make docs-check` → "docs-check OK".
- **Decisions:** chose host-`~/.local/bin` static binaries over toolbox-only install for
  the AWS/K8s CLIs, so `kind` shares the host's real Podman instead of a nested one —
  this is an environment detail, not an architecture decision, so no new ADR.
- **Incident (self-caught, no lasting harm):** the first version of the `make` wrapper
  called `toolbox run -c bedoux-aws make "$@"` (by name). Since the toolbox shares
  `$HOME`, `make` inside the toolbox also resolved to this same wrapper, recursing until
  the process/fork limit was hit (`fork: retry: Resource temporarily unavailable`).
  Killed with `pkill -9 -f "toolbox run"`; process count returned to normal (~430) within
  seconds; no kind/podman resources were ever created, nothing to tear down. Fixed by
  calling `/usr/bin/make` (absolute path) inside the toolbox; re-verified clean.
- **Next action:** owner approves the P1 gate; then P2.1 — FastAPI skeleton + health
  endpoint + tests (Compose). Separately, P3.1 must start with the rootless-Podman
  `Delegate=yes` fix before a real kind cluster can be created.
- **Blockers:** none for P1. Noted (not blocking): kind + rootless Podman gap for P3.

### 2026-07-18 — P0.6 GitHub push + ADR 0004 — Claude Code (operator: Tsogo)

- **Phase/task:** P0.6 complete; P0 gate ready for owner approval.
- **Changed:** ADR 0004 (start private, flip public before P9 after a full-history secrets
  sweep) supersedes 0003; repo `bedoux-tech/bedoux-commerce-cloud` created private via
  bedoux-vm's openclaw gh; collaborator invite to `tsogtbatjargal` accepted via API;
  `origin` added; `main` pushed.
- **AWS:** none. Estimated session cost: USD 0.
- **Commands/tests:** `gh repo create --private` (on bedoux-vm), `gh api PUT .../collaborators`,
  local `gh api PATCH user/repository_invitations/<id>`, `git push -u origin main` →
  `* [new branch] main -> main` (T-002).
- **Decisions:** ADR 0004 accepted by owner ("lets start with private").
- **Next action:** owner approves the P0 gate; gate commit activates P1 (P1.1 install/pin
  toolchain — note `make`, `xmllint`, `aws` missing on this host).
- **Blockers:** none.

### 2026-07-18 — P0 verification + commits — Claude Code (operator: Tsogo)

- **Phase/task:** P0 gate verification (T-001, T-003, T-005, T-006); P0.6 pending.
- **Changed:** five convention commits P0.1–P0.5 (`7633b33`..`4a3c30c`); START-HERE
  checkpoint refreshed; `scripts/check-tools.sh` now also requires `make` + `xmllint`
  (both missing from this Silverblue host's base — install in P1).
- **AWS:** none. Estimated session cost: USD 0.
- **Commands/tests:** docs-check logic OK (run via bash; `make` not on host yet);
  secrets sweep over `git ls-files` clean; T-005 cold-start test passed — a fresh agent
  reported state ("P0 nearly complete") and next action (P0.6 after visibility
  confirmation) from the spine alone, and caught the then-uncommitted checkpoint edit;
  T-006: the four slash commands are registered, `aws` CLI absent so `/aws-*` refuse
  safely. Diagram SVGs exported via podman `docker.io/rlespinasse/drawio-export`.
- **Decisions:** none new.
- **Next action:** P0.6 — owner confirms repo visibility (public per ADR 0003) and which
  GitHub account hosts it: local `gh` is authed as the owner's personal account, not
  `bedoux-tech`; then create + push, record T-002 evidence, close the P0 gate.
- **Blockers:** none.

### 2026-07-17 — P0 bootstrap — Claude Code (operator: Tsogo)

- **Phase/task:** P0.1–P0.4 complete; P0.5–P0.6 in progress.
- **Changed:** created git repo (`git init -b main`), `.gitattributes`, doc spine
  (`START-HERE.md`, `AGENTS.md`, `CLAUDE.md` shim, `docs/PROGRESS.md`,
  `docs/IMPLEMENTATION-PLAN.md`, `docs/TEST-PLAN.md`, `docs/HANDOFF.md`); merged and removed
  `docs/project-plan.md` + `docs/learning-roadmap.md`; ADRs 0002/0003 + index; 0001 →
  Accepted; edits to README, architecture, aws-session runbook, Makefile; `.claude/`
  settings + 4 slash commands; diagram revisions.
- **AWS:** none. Estimated session cost: USD 0.
- **Commands/tests:** `make docs-check` (see phase gate T-001 for final run).
- **Decisions:** ADR 0002 (defer Route53/ACM/RDS/S3/Secrets from MVP), ADR 0003
  (bedoux-tech public repo, direct-to-main until P6, commit convention).
- **Next action:** finish P0.5 diagrams, then P0.6 GitHub push after owner confirms
  visibility.
- **Blockers:** none.
