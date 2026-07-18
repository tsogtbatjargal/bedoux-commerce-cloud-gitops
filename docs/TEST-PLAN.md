# Test plan

Test IDs are referenced from phase gates in `docs/IMPLEMENTATION-PLAN.md`. Evidence for every
test lands in `docs/PROGRESS.md` (checklist line + session log), never in this file.

## Test roles

| Role | Responsibility |
|---|---|
| Implementing agent | runs automated tests and read-only verification commands, records evidence |
| Owner (Tsogo) | executes browser/console checklists, approves phase gates, confirms billing evidence |
| CI (from P6) | runs the automated suite on every pull request |

## T-0xx — P0 Bootstrap

- **T-001** — `make docs-check` passes: every `docs/diagrams/*.drawio` is valid XML, has a
  sibling exported `.svg`, and the spine files (`START-HERE.md`, `AGENTS.md`, `CLAUDE.md`,
  `docs/PROGRESS.md`, `docs/IMPLEMENTATION-PLAN.md`) exist.
- **T-002** — `git log --oneline` shows convention-formatted commits; `git remote -v` shows
  `bedoux-tech/bedoux-commerce-cloud`; push succeeded.
- **T-003** — secrets sweep: grep over tracked files finds no AWS account IDs, access keys,
  tokens, or personal email addresses.
- **T-004** — `docs/PROGRESS.md` P0 checklist fully checked with evidence; bootstrap session
  log entry present.
- **T-005** — cold-start test: a fresh agent session given only "Read START-HERE.md; report
  the current state and next action" answers correctly without reading outside the spine.
- **T-006** — `/catchup` runs end-to-end; `/aws-session-start` and `/aws-teardown-verify`
  correctly refuse while no AWS credentials are configured.

## T-01x — P1 Local tooling

- **T-011** — `make tools-check` reports every required tool available; versions recorded in
  `docs/local-tooling.md`.

## T-1xx — P2 Local application slice

- **T-101** — browser happy path: catalog → filter → detail → add to cart → submit order →
  confirmation, on Compose.
- **T-102** — unit + API integration tests pass (single command, no external credentials).
- **T-103** — OpenAPI docs page renders and matches the implemented endpoints.
- **T-104** — image scan results and image sizes recorded; containers run as non-root.

## T-2xx — P3 Local Kubernetes

- **T-201** — app reachable through kind Ingress (`/` frontend, `/api` API).
- **T-202** — `helm upgrade` rollout followed by a verified `helm rollback`.
- **T-203** — one deliberately broken deployment diagnosed from `kubectl` output alone;
  notes recorded.

## T-3xx — P4 AWS account readiness

- **T-301** — `aws sts get-caller-identity` succeeds with temporary (non-root) credentials.
- **T-302** — USD 20 budget with 5/10/16/20 alerts exists; a test/first alert email was
  received by the owner.
- **T-303** — owner-confirmed console checklists (root MFA, anomaly detection) recorded as
  evidence.

## T-4xx — P5 Manual EKS session

- **T-401** — public catalog page loads via the ALB DNS name.
- **T-402** — request traced ALB → target group → pod; notes recorded.
- **T-403** — one deliberate breakage (Ingress or IAM) diagnosed and fixed; notes recorded.
- **T-404** — teardown sweep clean: no EKS clusters, ALBs/target groups, NAT gateways,
  elastic IPs, unattached EBS volumes, or unexpected CloudFormation stacks remain.

## T-5xx / T-6xx — P6 Terraform + CI/CD

- **T-501** — `terraform apply` recreates the P5 environment; `terraform destroy` leaves an
  empty inventory (tag-based sweep).
- **T-601** — a green GitHub Actions run: lint/test/build/scan → OIDC auth → ECR push →
  Helm deploy → smoke test, against a live session cluster.
- **T-602** — a failed release rolled back from CI; evidence recorded.

## T-7xx — P7 Managed data services

- **T-701** — order flow works against short-lived Single-AZ RDS; migration job ran.
- **T-702** — product images served from S3 through the scoped workload identity.
- **T-703** — teardown sweep clean including RDS instances, snapshots, and subnet groups.

## T-8xx — P8 Observability

- **T-801** — CloudWatch dashboard populated; at least one alarm observed firing and
  recovering.
- **T-802** — four drill write-ups: unhealthy ALB target, failed pod, DB connection error,
  failed rollout.

## T-9xx — P9 Interview package

- **T-901** — 15-minute walkthrough dry-run completed within time; notes recorded.
- **T-902** — all six diagrams final with exported SVGs in `docs/diagrams/`.
