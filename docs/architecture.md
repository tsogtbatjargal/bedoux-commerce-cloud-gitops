# Architecture

## MVP profile vs production profile

The sections below describe the **production target**. The learning MVP deliberately defers
several services per [ADR 0002](decisions/0002-mvp-aws-service-deferrals.md):

| Concern | Learning MVP (P5–P6) | Production profile |
|---|---|---|
| DNS / entry | raw ALB DNS name | Route 53 custom domain |
| TLS | HTTP only | ACM certificate at the ALB |
| Database | in-cluster PostgreSQL (same chart as kind) | Multi-AZ RDS, tested backups |
| Product images | static files in the frontend container | S3 with scoped workload identity |
| Secrets | Kubernetes Secrets | AWS Secrets Manager |
| Nodes / replicas | 1 Spot node, 1 replica | private multi-AZ nodes, multiple replicas |
| Egress | no NAT Gateway | NAT / private service access as required |

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
6. The API reads product and order data from PostgreSQL.
7. The API accesses product images in S3 through a narrowly scoped workload
   identity.

## Delivery path

1. A pull request runs formatting, linting, tests, builds, and security scans.
2. A protected branch workflow exchanges GitHub's OIDC token for temporary AWS
   credentials.
3. Immutable images tagged with the Git commit SHA are pushed to ECR.
4. Helm deploys the selected image versions.
5. Kubernetes performs a rolling update and readiness gates traffic.
6. A smoke test verifies the public health and catalog endpoints.
7. A failed verification triggers an intentional Helm rollback.

## Identity boundaries

- **Human operator:** federated or role-based temporary AWS credentials; no
  routine root use and no committed access keys.
- **GitHub Actions:** dedicated OIDC role limited to required ECR, EKS, and
  deployment actions.
- **AWS Load Balancer Controller:** dedicated workload identity limited to
  required ELB and related APIs.
- **Bedoux API:** separate workload identity limited to its S3 objects and the
  required secret.
- **Kubernetes access:** EKS access entries plus Kubernetes authorization.

## Data design

- PostgreSQL is the system of record for products, inventory counts, and
  orders.
- S3 stores product images; the bucket is not publicly writable.
- The application stores no real payment-card or customer-sensitive data.
- Development seed data is synthetic and repeatable.

## Reliability design

The learning deployment uses one node and one replica to control cost. The
production target uses multiple nodes and application replicas across
Availability Zones, disruption budgets, topology spreading, autoscaling,
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
- [Runtime request path](diagrams/request-path.drawio) — the learning-profile ALB → web →
  api → RDS/S3 path in detail, including the ADR 0008 nginx-proxy hop
- [CI/CD delivery path](diagrams/ci-cd.drawio) — the GitHub Actions PR-validation and
  deploy-learning pipelines, including the OIDC exchange and Helm's atomic rollback
- [VPC and network](diagrams/vpc-network.drawio) — the no-NAT public-subnet learning VPC and
  RDS's security-group-scoped (not network-scoped) isolation
- [Identity boundaries](diagrams/identity.drawio) — all five distinct IAM identities with their
  exact trust conditions and permission scope
