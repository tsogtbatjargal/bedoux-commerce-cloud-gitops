---
name: aws-session-guardrail
description: Guard this repository's bounded AWS learning sessions and Kubernetes operational drills. Use before or during any AWS CLI, Terraform, EKS, IAM, RDS, S3, ECR, ALB, CloudWatch, kubectl, Helm, kind, failure-injection, recovery, or teardown work; use it for local Kubernetes drills too. Enforce the owner-approval, cost, identity, evidence, deadline, rollback, and clean-teardown boundaries without duplicating a separate Kubernetes-drill skill.
---

# AWS Session Guardrail

Resolve the repository root and read `AGENTS.md`, `START-HERE.md`, and the active state in
`docs/PROGRESS.md`.

Use `docs/runbooks/aws-session.md` as the canonical session and Kubernetes-drill procedure. Read
`docs/cost-guardrails.md` and any phase-specific runbook named by the active checklist item.

For local kind work, follow the runbook's Kubernetes drill integration and record `AWS: none`.
For a standalone read-only AWS check, verify the exact identity and region, sanitize output, and
do not imply that a billable session is open. For EKS drills or any AWS mutation, follow the full
AWS session boundary. Never mutate AWS merely because this skill was invoked; require the
repository's explicit owner approval and stop conditions.

Keep evidence sanitized. End an AWS/EKS drill only after recovery, Kubernetes cleanup, teardown,
and the inventory sweep required by the canonical runbook.
