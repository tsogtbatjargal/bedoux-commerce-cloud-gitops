# Implementation plan

This plan replaces the earlier `project-plan.md` and `learning-roadmap.md` (merged 2026-07-17).
Execution state lives only in `docs/PROGRESS.md`. Agents may not start a later phase early;
every phase gate requires owner approval recorded as its own commit
(`Phase N gate approved by owner; activate Phase N+1`).

## Goal

Build a compact commerce system that demonstrates the skills expected from a cloud, platform,
or DevOps engineer:

- application containerization;
- Kubernetes workload design and troubleshooting;
- AWS networking, identity, compute, storage, and managed databases;
- infrastructure as code;
- secure CI/CD;
- logs, metrics, dashboards, and alarms;
- cost-aware architectural decisions;
- operational documentation and incident response.

This is a production-oriented reference implementation. It must never claim real customers,
revenue, uptime, traffic, or payment processing that it has not actually handled.

## Functional scope (first release)

- a seeded product catalog;
- search and category filtering;
- product detail pages;
- a browser-based cart (client-side);
- order submission and confirmation;
- an API health endpoint;
- PostgreSQL migrations and repeatable seed data;
- product images served as static files by the frontend container (S3 arrives in P7 via the
  adapter boundary from ADR 0001).

Authentication, real payment processing, asynchronous order fulfillment, Redis, WAF, and
multi-region recovery are later enhancements.

## Environment profiles

### Local

- Docker/Podman Compose for the fastest application feedback loop.
- `kind` for Kubernetes learning and manifest verification.
- PostgreSQL container for persistence.
- Filesystem image storage behind the adapter boundary (MinIO optional later).
- No AWS account or AWS charge required.

### AWS learning

- Created only for planned sessions and destroyed the same day.
- One EKS cluster on a current standard-support Kubernetes version.
- One small managed Spot worker node where capacity permits.
- One shared ALB with path-based routing, reached by its **raw ALB DNS name over HTTP**.
- One replica per application.
- **In-cluster PostgreSQL** (same chart as kind) until P7; small Single-AZ RDS only during
  P7 database sessions.
- Three-day CloudWatch log retention.
- No NAT Gateway.

This profile is not presented as highly available.

### Production target (documented, not deployed)

- Route 53 custom domain and ACM TLS at the ALB.
- Private nodes across multiple Availability Zones.
- Multiple replicas, disruption budgets, and topology spreading.
- Multi-AZ RDS with backups and tested recovery; S3 product images; Secrets Manager.
- Autoscaling, longer telemetry retention, private AWS service access, stricter network
  policies, and WAF.

The production target is documented and represented in infrastructure code, but it is not
kept running on the learning budget.

## Deferred to production profile / later phases

Per [ADR 0002](decisions/0002-mvp-aws-service-deferrals.md):

| Item | Learning MVP uses | Returns in |
|---|---|---|
| Route 53 + custom domain | raw ALB DNS name | production profile (documented only) |
| ACM / TLS at the ALB | HTTP | production profile (documented only) |
| Amazon RDS | in-cluster PostgreSQL | P7 (short-lived Single-AZ sessions) |
| S3 product images | static files in the frontend container | P7 (via ADR 0001 adapter) |
| Secrets Manager | Kubernetes Secrets | P7 |
| NAT Gateway | not used | never in the learning profile |

## Phases

Task IDs are `P<phase>.<n>`; gate evidence uses `T-NNN` ids from `docs/TEST-PLAN.md`.

### P0 — Bootstrap ($0)

- **Goal:** agent-agnostic doc spine, git repo, `.claude` config, revised diagrams.
- **Steps:** P0.1 doc spine; P0.2 ADRs 0002/0003 + index, 0001 accepted; P0.3 README /
  architecture / runbook / Makefile updates; P0.4 `.claude` settings + slash commands;
  P0.5 diagrams revised + SVG exports; P0.6 GitHub repo created and pushed.
- **Gate:** T-001..T-006 (includes the fresh-agent cold-start test).
- **Rollback:** delete the repo directory; nothing external exists.

### P1 — Local tooling ($0)

- **Goal:** pinned toolchain: aws, kubectl, eksctl, kind, helm, terraform, node, python,
  podman; `make tools-check` green.
- **Steps:** P1.1 install/pin missing tools; P1.2 record versions in `docs/local-tooling.md`.
- **Gate:** T-011 `make tools-check` all-green output in PROGRESS.
- **Rollback:** remove installed tools; nothing else depends on them yet.

### P2 — Local application slice on Compose ($0)

- **Goal:** FastAPI API (health, catalog, order submit) + PostgreSQL container + React
  catalog/cart frontend, all as containers under Compose, with migrations, seed data, and
  tests. Multi-stage non-root images from day one.
- **Steps:** P2.1 API skeleton + health endpoint + tests; P2.2 schema, migrations, seed data;
  P2.3 catalog + order endpoints + integration tests; P2.4 React catalog/detail/cart/confirm
  pages (client-side cart, static images); P2.5 Compose file + image scan + size record.
- **Gate:** T-101 catalog→order happy path in the browser; T-102 unit/API tests pass;
  T-103 OpenAPI page renders; T-104 images scanned, sizes recorded.
- **Rollback:** `compose down -v`; delete feature branch.

### P3 — Local Kubernetes on kind ($0)

- **Goal:** the same app on kind: plain manifests first, then a Helm chart; in-cluster
  PostgreSQL; probes, resource limits, ConfigMaps/Secrets, Ingress.
- **Steps:** P3.1 kind cluster + namespace + plain manifests; P3.2 probes, limits, config;
  P3.3 Ingress with `/` and `/api` routing; P3.4 convert to Helm chart (`helm lint` clean);
  P3.5 drills — scale, pod deletion, broken config, rollback.
- **Gate:** T-201 app reachable through kind Ingress; T-202 `helm upgrade` rollout +
  `helm rollback` drill evidence; T-203 broken-deployment diagnosis notes.
- **Rollback:** `kind delete cluster`.

### P4 — AWS account readiness (~$0)

- **Goal:** account safe before any resource: root MFA, temporary admin credentials, region
  pinned, USD 20 budget with 5/10/16/20 alerts, Cost Anomaly Detection, standard tags agreed,
  teardown runbook rehearsed on paper.
- **Steps:** P4.1 root MFA + credential review (owner console checklist); P4.2 budget +
  alerts + anomaly detection (owner console checklist); P4.3 pin region, record in PROGRESS;
  P4.4 dry-run the session runbook end-to-end without creating resources.
- **Gate:** T-301 `aws sts get-caller-identity` with temporary credentials; T-302 budget
  alert email received; T-303 owner-confirmed console checklists recorded.
- **Rollback:** disable alerts; nothing billable exists.

### P5 — Manual EKS session ($2–4 per session)

- **Goal:** one eksctl cluster; ECR push; AWS Load Balancer Controller via Helm; app deployed
  manually (in-cluster PostgreSQL) and reachable via the **ALB DNS name**; request traced
  ALB→pod; one deliberate breakage diagnosed; **same-day teardown**.
- **Steps:** P5.1 session start per runbook + eksctl cluster; P5.2 ECR repos + image push;
  P5.3 ALB controller + Ingress + reachability; P5.4 trace + break/fix drill; P5.5 teardown
  + clean sweep.
- **Gate:** T-401 public catalog page via ALB DNS; T-402 trace notes; T-403 break/fix notes;
  T-404 teardown sweep clean (via `/aws-teardown-verify`).
- **Rollback:** `eksctl delete cluster` + teardown sweep — at any point in the session.

### P6 — Terraform, then CI/CD ($2–4 per session)

- **Goal:** Terraform recreates everything P5 built (VPC, EKS, node group, ECR, IAM, ALB
  controller permissions); then GitHub Actions with OIDC: lint/test/build/scan, push to ECR,
  Helm deploy, smoke test, rollback verification. Terraform state bucket is added to the
  persistent-resource allowlist. Branch protection turns on here (ADR 0003).
- **Steps:** P6.1 Terraform modules + `plan` reviewed cold; P6.2 apply/verify/destroy cycle;
  P6.3 OIDC role + PR pipeline (no AWS); P6.4 deploy pipeline against a live session cluster;
  P6.5 rollback drill from CI.
- **Gate:** T-501 `terraform destroy` leaves an empty inventory; T-601 green pipeline run
  deploying to a session cluster; T-602 CI rollback evidence.
- **Rollback:** `terraform destroy`; disable workflows.

### P7 — Managed data services ($3–5 per session)

- **Goal:** the deferred services return: short-lived Single-AZ RDS (with a migration job),
  S3 product images through the ADR 0001 adapter, Secrets Manager for the DB credential.
- **Steps:** P7.1 RDS module + connectivity + migration job; P7.2 S3 bucket + adapter flip +
  workload identity; P7.3 Secrets Manager integration; P7.4 same-day teardown incl. snapshot
  policy check.
- **Gate:** T-701 order flow against RDS; T-702 images served from S3 via scoped identity;
  T-703 teardown sweep clean including RDS snapshots/subnet groups.
- **Rollback:** destroy + flip adapter back to in-cluster/static mode (config only).

### P8 — Observability and operations drills ($2–4 per session)

- **Goal:** structured JSON logs with request IDs, CloudWatch logs (3-day retention),
  a small dashboard, alarms (error rate, unhealthy targets, pod restarts, DB utilization),
  and troubleshooting runbooks proven by drills.
- **Steps:** P8.1 app logging + request IDs (local first); P8.2 CloudWatch wiring +
  dashboard + alarms; P8.3 drills — unhealthy ALB target, failed pod, DB connection error,
  failed rollout; P8.4 write/verify troubleshooting runbooks.
- **Gate:** T-801 dashboard + firing alarm evidence; T-802 four drill write-ups.
- **Rollback:** standard teardown; log groups auto-expire.

### P9 — Interview package ($0)

- **Goal:** a timed 15-minute technical tour, final diagrams, and an evidence reel.
- **Steps:** P9.1 walkthrough script (problem 1 min, architecture + request path 3, K8s/AWS
  responsibilities 3, CI/CD + identity 3, observability + troubleshooting 3, cost/reliability
  trade-offs 2); P9.2 all six diagrams final + exported; P9.3 dry-run, timed, refined.
- **Gate:** T-901 timed dry-run recorded/noted; T-902 diagram set complete.
- **Rollback:** n/a.

## Parallel track — free AWS foundations (non-gating)

AWS Educate and free Builder Labs for IAM, VPC/subnets/routing/security groups, EC2/EBS, S3
permissions, RDS connectivity, and cost estimation. Do these any time; log each lab in the
PROGRESS session log (what was created, who authorized it, how it was inspected, how it was
deleted). This track never blocks a phase gate.

## Definition of done

The project is complete when:

- a new developer can run the application locally from the README;
- the application passes automated tests and runs on local Kubernetes;
- Terraform can create and destroy the learning AWS environment;
- GitHub Actions builds immutable images and deploys them without long-lived AWS keys;
- the public request path, identity path, and deployment path are documented;
- a failed deployment can be diagnosed and rolled back using a runbook;
- the AWS resource inventory is empty after teardown, except for explicitly approved
  persistent resources;
- the complete architecture can be explained in a 15-minute technical tour.
