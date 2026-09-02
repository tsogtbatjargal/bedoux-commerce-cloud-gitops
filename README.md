# Bedoux Commerce Cloud

> **New agent or returning after a break? Start at [START-HERE.md](START-HERE.md).**
> Execution state lives only in [docs/PROGRESS.md](docs/PROGRESS.md); operating rules in
> [AGENTS.md](AGENTS.md).

Bedoux Commerce Cloud is a production-oriented reference implementation of a
small commerce platform running on Amazon EKS. The application is intentionally
small; the project focuses on Kubernetes operations, AWS infrastructure,
delivery automation, security, observability, cost control, and the ability to
explain the system clearly in a technical interview.

The project is developed locally first and deployed to AWS only in short-lived
learning sessions. This keeps the monthly AWS target at **USD 20 or less**.

## Intended user journey

1. Browse and filter a product catalog.
2. View product details and images.
3. Add products to a cart.
4. Submit an order.
5. View an order confirmation.

The first release does not process real payments or customer data.

## Proposed stack

- React, Vite, and TypeScript frontend
- FastAPI backend
- PostgreSQL
- Docker and local Kubernetes with `kind`
- Amazon EKS with managed Spot node groups for short-lived learning sessions (one by default;
  two AZ-pinned one-node groups in the opt-in P11 HA profile)
- Amazon ECR, S3, RDS PostgreSQL, ALB, and CloudWatch
- Terraform for AWS infrastructure
- Helm for Kubernetes packaging
- GitHub Actions with AWS OIDC for CI/CD

## Documentation

| Doc | Purpose |
|---|---|
| [START-HERE.md](START-HERE.md) | Session entry point: checkpoint, boundaries, resume protocol |
| [AGENTS.md](AGENTS.md) | Canonical tool-agnostic operating rules (Claude Code / Codex / human) |
| [docs/PROGRESS.md](docs/PROGRESS.md) | **Only authoritative execution state** + session log |
| [docs/IMPLEMENTATION-PLAN.md](docs/IMPLEMENTATION-PLAN.md) | Phases P0–P14 with gates, rollback, and per-session cost |
| [docs/TEST-PLAN.md](docs/TEST-PLAN.md) | T-NNN test ids referenced by phase gates |
| [docs/HANDOFF.md](docs/HANDOFF.md) | Copy-paste prompt to continue in a fresh agent session |
| [docs/architecture.md](docs/architecture.md) | Request/delivery/identity paths; MVP vs production profile |
| [docs/cost-guardrails.md](docs/cost-guardrails.md) | Budget, alerts, prohibited resources, persistent allowlist |
| [docs/resource-right-sizing.md](docs/resource-right-sizing.md) | P14.1 measured resource derivation, retained values, and rollback |
| [docs/spot-diversification.md](docs/spot-diversification.md) | P14.3 bounded Spot diversification and interruption-handling review |
| [docs/local-tooling.md](docs/local-tooling.md) | Workstation toolchain and pinned versions |
| [docs/runbooks/aws-session.md](docs/runbooks/aws-session.md) | Before/during/teardown checklists for every AWS session |
| [docs/workflows/](docs/workflows/) | Canonical phase and GitHub branch/PR operating workflows |
| [.agents/skills/](.agents/skills/) | Three canonical repo-scoped skills that route agents to canonical docs |
| [.claude/skills/](.claude/skills/) | Claude Code discovery wrappers for those same three skill bodies |
| [docs/decisions/](docs/decisions/README.md) | Architecture decision records (ADR index) |
| [docs/diagrams/](docs/diagrams/) | draw.io sources + exported SVGs |

## Delivery principle

Every milestone must be demonstrable locally before it is attempted in AWS.
AWS resources are not created until account security, billing alerts, resource
inventory, and a verified destruction procedure are complete.
