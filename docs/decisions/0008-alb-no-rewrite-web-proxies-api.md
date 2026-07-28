# ADR 0008: ALB Ingress can't rewrite paths — web's own nginx proxies /api internally

- Status: Accepted
- Date: 2026-07-28

## Context

`docs/architecture.md`'s request path (written in P0, before any real ALB existed) says
"`/` routes to the frontend Service and `/api` routes to the API Service" via the ALB
Ingress directly, mirroring the kind/nginx-ingress shape built in P3.3
(`nginx.ingress.kubernetes.io/rewrite-target`, two `Ingress` objects, `/api` prefix
stripped before reaching the `api` Service).

Building P5.3's real `Ingress` against the AWS Load Balancer Controller surfaced that this
assumption was wrong: the ALB Ingress Controller has no annotation equivalent to
`rewrite-target` — it can route by path but cannot rewrite the path before forwarding.
Routing `/api/*` straight to the `api` Service (as the kind profile does after rewriting)
would send the literal `/api/products` to the API, which only serves routes at
`/products` (no `/api` prefix in the FastAPI app itself) — a 404 on every request.

The web container's `nginx.conf.template` (`apps/web/nginx.conf.template`, built in P2.4
for Compose) already has exactly this logic — a `location /api/ { proxy_pass
http://${API_UPSTREAM}/; }` block that strips the prefix and forwards to the API. It has
been present and correctly built into every `web` image since P2.4, but sat unused once
the app moved to Kubernetes, because the nginx Ingress's own rewrite made it redundant
there.

## Decision

For the ALB profile only (`charts/bedoux/values-aws.yaml`, `ingress.controller: alb`), the
chart emits a **single** `Ingress` (`alb.ingress.kubernetes.io/scheme: internet-facing`,
`target-type: ip`) with one rule, `/` → the `web` Service. There is no separate `/api`
rule and no rewrite annotation. `/api` requests reach the ALB, get routed to a `web` pod
like every other request, and the web pod's own nginx forwards them to `api:8000`
internally over the cluster network, stripping the prefix exactly as it already does for
Compose.

The kind/nginx profile (`ingress.controller: nginx`, the existing default) is unchanged —
two `Ingress` objects, `rewrite-target`, direct-to-`api` routing — since nginx *does*
support rewrite and that path was already verified in P3.3/P3.5.

`charts/bedoux/templates/ingress.yaml` branches on `.Values.ingress.controller` to emit
one shape or the other; nothing in `apps/api` or `apps/web` changed — the AWS profile
activates code that already existed for Compose and had simply never been exercised in a
Kubernetes deployment before.

## Consequences

- `docs/architecture.md`'s request-path list needs a corrected step 4/5 reflecting that
  `/api` reaches the API Service via the web pod's internal proxy, not a direct ALB
  target-group rule — updated alongside this ADR.
- Only one ALB is created for the whole app (both `/` and `/api` share it via
  `group.name: bedoux`), keeping cost and complexity down — the alternative (an ALB
  Ingress per path, or adding a second ingress controller just for rewrite support) would
  have meant more moving parts for no real benefit at this scale.
- The API is not directly internet-reachable in the AWS profile — every request passes
  through a web pod first. This is consistent with the project's existing kill-switch/
  request-bounds posture (ADR-pending-decision #4): one less direct network path to the
  API from the public ALB DNS name.
- If a future phase needs the API reachable without going through web (e.g. a mobile
  client), that requires either switching the AWS profile to a second ALB with real
  path-based rules and moving rewrite logic into the API itself (accepting `/api`-prefixed
  routes), or adding an nginx-ingress-style controller to EKS — a real architecture
  decision to make consciously then, not implied by this one.
