# P14.3 Spot diversification and interruption-handling review

## Decision for the bounded learning profile

Use the same-shape x86_64 Spot pool `t3.medium` and `t3a.medium` for the default
one-node profile and the opt-in P11 HA profile. Keep the existing limits unchanged:

- default profile: `min = desired = max = 1`;
- P11 HA profile: two one-node AZ-pinned groups with aggregate
  `min = desired = max = 2`;
- 20-GiB gp3 root volume, public-only subnets, and no NAT Gateway;
- `SPOT` remains the only capacity type in these profiles.

Both types are x86_64 general-purpose instances with the same 2-vCPU/4-GiB
shape. This preserves the pod-scheduling assumptions while allowing EKS to use
more Spot capacity pools. The Terraform variable is already a list, and the
profiles now exercise that capability rather than pinning one pool.

Amazon EKS recommends multiple instance types for Spot managed node groups to
increase the available capacity pools. Its same-vCPU/same-memory recommendation
is specifically important with Cluster Autoscaler; this project does not run
Cluster Autoscaler, but retaining the same shape also avoids changing the fixed
profile's scheduling and resource assumptions. The project does not claim that
either type is currently available or cheaper in `ca-central-1`; regional
capacity and price must be checked during any future bounded AWS session.

## Interruption-handling review

EKS managed Spot node groups enable EC2 Spot Capacity Rebalancing and attempt to
launch a replacement, then cordon and drain the at-risk node. The process is
best effort: workloads must remain interruption-tolerant and cannot assume the
replacement is Ready before draining starts.

The ordinary Bedoux profile follows AWS's current workload guidance: the API
and web renders each set `terminationGracePeriodSeconds: 30`, and neither emits
a `lifecycle`/preStop hook. PR validation asserts exactly those two 30-second
grace periods and zero lifecycle blocks so a long shutdown path cannot be added
silently.

The opt-in AWS-HA overlay is a deliberate exception: ADR 0019 retains a
60-second grace period with a 45-second preStop hold to satisfy the separately
measured ALB deregistration contract. T-1103 proved that profile under a bounded
node drain, but it may not receive its full grace period during a real concurrent
Spot reclamation. P14.3 does not rewrite that accepted, live-proven tradeoff.

ADR 0017's phrase "exactly two `t3.medium` nodes" records the P11-era profile.
P14.3 widens only the eligible instance-type list to `t3.medium`/`t3a.medium`;
it preserves ADR 0017's decision invariants of two AZ-pinned one-node groups and
an aggregate two-node ceiling. The accepted ADR is therefore not amended or
superseded.

References: [EKS managed node group Spot and interruption guidance](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html),
[EKS launch-template guidance](https://docs.aws.amazon.com/eks/latest/userguide/launch-templates.html),
and [EC2 Nitro instance families](https://docs.aws.amazon.com/ec2/latest/instancetypes/ec2-nitro-instances.html).

## Rollback and scope

This is a configuration/documentation-only change. Restore
`node_instance_types = ["t3.medium"]` in the relevant temporary profile if a
future session finds a regional capacity or compatibility issue; do not widen
the node count to compensate. No AWS resources were changed for this review.
