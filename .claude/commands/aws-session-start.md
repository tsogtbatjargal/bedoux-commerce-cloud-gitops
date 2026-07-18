---
description: Open an AWS learning session - walk the pre-session checklist, refuse on stop conditions
---

Open an AWS learning session by walking the "Before the session" checklist in
`docs/runbooks/aws-session.md`, one item at a time. Concretely:

1. `aws sts get-caller-identity` — confirm the expected account and a temporary (non-root)
   identity. If credentials are missing or the account is uncertain: **refuse to open the
   session** and stop.
2. Confirm the pinned region from `docs/PROGRESS.md` Known facts (never infer it from a
   console URL). If no region is pinned, stop — that is P4.3.
3. Month-to-date cost: `aws ce get-cost-and-usage` for the current month, plus
   `aws budgets describe-budgets`. If projected monthly cost exceeds USD 16, refuse (stop
   condition).
4. Leftover sweep — all read-only: `aws eks list-clusters`,
   `aws elbv2 describe-load-balancers`, `aws rds describe-db-instances`,
   `aws ec2 describe-nat-gateways`, `aws ec2 describe-addresses`,
   `aws ec2 describe-volumes --filters Name=status,Values=available`,
   `aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE`,
   `aws resourcegroupstaggingapi get-resources --tag-filters Key=project,Values=bedoux-commerce-cloud`.
   Any resource that cannot be explained → refuse and record it as a blocker.
5. Ask the operator for the session goal (which task ID) and the planned end time; state the
   session's cost estimate from the phase table in `docs/IMPLEMENTATION-PLAN.md`.
6. Record the session start in `docs/PROGRESS.md` (session log entry opened with start time,
   task ID, planned end time, cost estimate).

Any stop condition in `docs/runbooks/aws-session.md` overrides everything else. Only after
every checklist item passes may resource-creating work begin.
