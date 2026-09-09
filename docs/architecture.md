# Architecture

The separate [production-hosting assessment](production-hosting-plan.md) evaluates a lower-cost
catalog launch for bedoux.ca. ADR 0025 is Proposed; the implemented paths and earlier production
target below are unchanged. No persistent hosting has been deployed by that assessment.

The [GitOps expansion plan](gitops-expansion-plan.md) and Proposed ADR 0026 describe a future
app/environment repository split with Argo CD and Argo Rollouts. They do not describe the current
push-based runtime as already migrated; implementation and live evidence remain pending.

## Learning baseline, proven opt-in profiles, and production target

ADR 0002 defined the P5–P6 baseline deferrals. Later phases proved selected components in
bounded sessions without claiming that the complete production target was deployed:

| Concern | Default learning baseline | Proven opt-in session profile | Production target |
|---|---|---|---|
| DNS / entry | raw ALB DNS name | P12 Route 53 aliases for `bedoux.ca` and `www`; aliases removed after proof | durable Route 53 custom domain |
| TLS | HTTP | P12 ACM TLS and HTTP→HTTPS redirects | ACM certificate at the ALB |
| Database | in-cluster PostgreSQL | P7 short-lived Single-AZ RDS | Multi-AZ RDS with tested backups |
| Product images | frontend-container static files | P7 S3 with scoped workload identity | durable S3 with lifecycle and recovery policy |
| Secrets | Kubernetes Secret | P7 Secrets Manager with scoped workload identity | managed secret rotation |
| Nodes / replicas | 1 Spot node, 1 replica | P11 two AZ-pinned Spot nodes and two stateless replicas | private multi-AZ nodes, multiple replicas, bounded autoscaling |
| Delivery | Helm atomic rolling update | P13 controller-native 90/10 canary | controlled progressive delivery with production SLOs |
| Egress | no NAT Gateway | no NAT Gateway in every learning profile | private service access or controlled NAT as required |

## Runtime request path

1. A user resolves the application hostname through Route 53 when a custom
   domain is enabled.
2. An internet-facing Application Load Balancer terminates TLS using ACM.
3. The AWS Load Balancer Controller reconciles the Kubernetes Ingress and AWS
   target groups.
4. The ALB Ingress has a single rule: `/` routes to the frontend Service. ALB
   `ip` target mode sends traffic directly to frontend pod IP addresses.
5. The frontend pod's own nginx reverse-proxies `/api/*` requests to the API
   Service internally, over the cluster network, stripping the prefix — ALB
   has no path-rewrite annotation, so this happens one hop further in than a
   direct ALB target-group rule would (see
   [ADR 0008](decisions/0008-alb-no-rewrite-web-proxies-api.md)). The API is
   never directly reachable from the public ALB DNS name.
6. The API reads product and order data from in-cluster PostgreSQL in the baseline or Single-AZ
   RDS in the bounded managed-data profile.
7. The API returns frontend-static image URLs in the baseline or accesses S3 through a narrowly
   scoped workload identity when the managed-image profile is enabled.

## Delivery path

1. A pull request runs formatting, linting, tests, builds, security scans, SPDX SBOM generation,
   and a real `cosign` sign/verify proof against an ephemeral local registry. The PR job uses an
   ephemeral key and receives no GitHub OIDC token or AWS credential.
2. The `main` deployment workflow exchanges GitHub's OIDC token for temporary AWS credentials.
   Because the private-repository plan cannot enforce server-side branch protection, ADR 0010's
   local guardrail and reviewed-PR discipline remain compensating controls.
3. Immutable images tagged with the Git commit SHA are pushed to ECR.
4. The workflow generates short-retention SPDX JSON artifacts and uses keyless `cosign` signing;
   the certificate identity is the exact `deploy-learning.yml` workflow on `main`.
5. The Helm step re-verifies both signatures against that identity and GitHub's OIDC issuer, then
   deploys the exact verified digests rather than mutable tags.
6. Kubernetes performs a rolling update and readiness gates traffic.
7. A smoke test verifies the public health and catalog endpoints.
8. A failed verification stops before Helm; a failed signed rollout triggers intentional Helm
   atomic rollback.

## Identity boundaries

- **Human operator:** non-root `bedoux-admin` named profile with MFA; no routine root use and no
  credentials committed to the repository.
- **GitHub Actions:** dedicated OIDC role limited to required ECR, EKS, and
  deployment actions.
- **AWS Load Balancer Controller:** dedicated workload identity limited to
  required ELB and related APIs.
- **Bedoux API:** separate workload identity limited to its S3 objects and the
  required secret.
- **Kubernetes access:** EKS access entries plus Kubernetes authorization.

## Data design

- PostgreSQL is the system of record for products, inventory counts, and orders; the baseline uses
  in-cluster PostgreSQL and the bounded P7 profile used Single-AZ RDS.
- The baseline serves static product images from the frontend container. The bounded P7 profile
  stored them in a non-publicly-writable S3 bucket and returned presigned URLs.
- The application stores no real payment-card or customer-sensitive data.
- Development seed data is synthetic and repeatable.

## Reliability design

The default learning deployment uses one node and one replica to control cost. P11's opt-in,
same-day HA profile temporarily used two AZ-pinned one-node Spot groups and two stateless
replicas to prove bounded node-loss recovery. That profile did not claim PostgreSQL HA and did
not replace the default baseline. The production target uses multiple nodes and application
replicas across Availability Zones, disruption budgets, topology spreading, autoscaling,
Multi-AZ RDS, tested backups, and controlled deployments.

The difference is deliberate and documented as a cost-versus-availability
decision.

## Observability design

- The API emits one structured JSON completion event to stdout for each HTTP request. Its fixed
  schema includes UTC timestamp, level, event, request ID, method, path, status code, and duration.
- A valid incoming `X-Request-ID` UUID is normalized and returned; otherwise the API creates one
  and returns it in the response header. Request bodies, query strings, headers, credentials, and
  database URLs are never included in this event.
- P8.2's opt-in EKS CloudWatch Observability add-on forwards those stdout events to the temporary
  Container Insights application log group through an IRSA role restricted to the CloudWatch agent
  ServiceAccount. The log group has three-day retention. Two JSON metric filters derive request
  count and 5xx count; a dashboard derives 5xx rate and displays ALB unhealthy targets, namespace
  pod restarts, and short-lived RDS CPU utilization. The collector, dashboard, metric filters, and
  notification-free alarms are session-temporary; the local P8.1 boundary itself has no AWS
  dependency.

## Current diagrams

- [System context](diagrams/system-context.drawio)
- [Learning and delivery path](diagrams/learning-path.drawio)
- [Runtime request path](diagrams/request-path.drawio) — the bounded ALB → web → api → RDS/S3
  path, including ADR 0008's nginx-proxy hop plus the proven P12 TLS and P13 90/10 overlays
- [CI/CD delivery path](diagrams/ci-cd.drawio) — the GitHub Actions PR-validation and
  deploy-learning pipelines, including OIDC, SBOM/signature gates, Helm atomic rollback, and
  P13's reconciled canary path
- [VPC and network](diagrams/vpc-network.drawio) — the no-NAT public-subnet learning VPC and
  RDS's security-group-scoped (not network-scoped) isolation
- [Identity boundaries](diagrams/identity.drawio) — all five distinct IAM identities with their
  exact trust conditions and permission scope
- [P10–P14 optimization evidence](diagrams/optimization-track.drawio) — measured security,
  availability, TLS, progressive-delivery, performance, and cost outcomes added after the P9
  interview baseline
