---
description: Verify AWS teardown is complete - sweep for leftover billable resources and record evidence
---

Verify the AWS environment is actually gone. Walk the "Teardown" checklist in
`docs/runbooks/aws-session.md` with concrete read-only commands in the pinned region:

1. `aws sts get-caller-identity` — confirm account. If no credentials, report that there is
   nothing to verify and stop.
2. EKS: `aws eks list-clusters` → must be empty (or match the persistent allowlist in
   `docs/cost-guardrails.md`).
3. Load balancing: `aws elbv2 describe-load-balancers` and
   `aws elbv2 describe-target-groups` → empty.
4. NAT + EIP: `aws ec2 describe-nat-gateways --filter Name=state,Values=available` and
   `aws ec2 describe-addresses` → empty.
5. Compute + storage: `aws ec2 describe-instances --filters Name=instance-state-name,Values=running,pending`
   and `aws ec2 describe-volumes --filters Name=status,Values=available` → empty.
6. RDS: `aws rds describe-db-instances`, `aws rds describe-db-snapshots --snapshot-type manual`
   → match allowlist.
7. Stacks: `aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE ROLLBACK_COMPLETE`
   → no eksctl/app stacks remain.
8. Tag sweep: `aws resourcegroupstaggingapi get-resources --tag-filters Key=project,Values=bedoux-commerce-cloud`
   → only allowlisted persistent resources (ECR repos, Terraform state bucket once created).
9. Report every non-empty result to the operator. **A leftover resource is a billing
   incident**: name it, state its hourly cost if known, and ask the operator before deleting
   anything (deletion commands are not allowlisted on purpose).
10. Append the sweep results as teardown evidence to the open session entry in
    `docs/PROGRESS.md`, and remind the operator to recheck Billing after usage data updates.
