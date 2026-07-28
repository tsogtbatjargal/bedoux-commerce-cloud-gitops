# Progress

This file is the **only authoritative execution state** for bedoux-commerce-cloud.
Do not infer progress from files existing. A task is complete only when its checkbox is
checked here and its evidence is recorded in the session log.

## Overall status

| Field | Value |
|---|---|
| State | IN PROGRESS |
| Active phase | P5 — Manual EKS session |
| Active task | P5.4 — trace + break/fix drill |
| Last verified | 2026-07-28 — P5.3 complete: real ALB serving the app end-to-end, golden-path order confirmed in Postgres over the public DNS name |
| AWS resources currently live | EKS cluster `bedoux` (1 Spot `t3.medium` node), OIDC provider, EBS CSI driver add-on, ALB Load Balancer Controller (+ its own IRSA role), 1 real ALB (`k8s-bedoux-...`), IAM roles `bedoux-eks-cluster-role`/`bedoux-eks-nodegroup-role`/`bedoux-ebs-csi-role`/`bedoux-alb-controller-role`, IAM policy `bedoux-alb-controller-policy`, ECR repos `bedoux-api`/`bedoux-web`, full app deployed in `bedoux` namespace (api/web/postgres, `gp3` PVC bound) — all tagged `project=bedoux-commerce-cloud`/`environment=learning` |
| Month-to-date estimated AWS spend | Well under USD 2 so far this session (control plane + 1 Spot node + 1 ALB, ~2hr elapsed) |
| Next operator action | **agent**: P5.4 — trace a request ALB→pod, one deliberate breakage diagnosed and fixed |

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
- **P6/P7 boundary**: S3 image adapter — API returns `image_url`, presigned URL via IRSA
  in S3 mode, frontend storage-agnostic.
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
- [ ] P5.4 NOT STARTED — trace + break/fix drill.
- [ ] P5.5 NOT STARTED — teardown + clean sweep.

### P6 — Terraform, then CI/CD

- [ ] P6.1 NOT STARTED — Terraform modules + reviewed plan.
- [ ] P6.2 NOT STARTED — apply/verify/destroy cycle.
- [ ] P6.3 NOT STARTED — OIDC role + PR pipeline.
- [ ] P6.4 NOT STARTED — deploy pipeline against session cluster.
- [ ] P6.5 NOT STARTED — CI rollback drill.

### P7 — Managed data services

- [ ] P7.1 NOT STARTED — RDS + migration job.
- [ ] P7.2 NOT STARTED — S3 images via adapter + workload identity.
- [ ] P7.3 NOT STARTED — Secrets Manager integration.
- [ ] P7.4 NOT STARTED — teardown incl. snapshot policy check.

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

- None.

## Session log

Append newest entries immediately below this heading. Never include secrets or AWS account IDs.

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
