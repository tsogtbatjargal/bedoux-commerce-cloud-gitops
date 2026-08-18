# ADR 0017: Pin the P11 HA node groups by AZ and permit one-AZ failover

- Status: Accepted
- Date: 2026-08-18
- Accepted by owner: 2026-08-18 (technical design; apply remains separately gated)

## Context

P11.3 used one EKS managed Spot node group with two subnets and an aggregate size of two. Both
initial nodes landed in the same Availability Zone. The chart's hard `minDomains: 2` /
`DoNotSchedule` topology constraint then left the second API and web replicas Pending. This
proved that supplying two subnets does not guarantee the one-node-per-AZ baseline required by
T-1103.

The same hard constraint also prioritizes perfect spread over availability after one AZ becomes
unschedulable: replacement stateless replicas cannot all move to the surviving AZ. P11.4 needs
the opposite behavior during the declared failure window while retaining cross-AZ preference
under normal conditions.

## Decision

For the opt-in P11 HA profile only, create two fixed one-node managed Spot node groups, each
pinned to one of the two configured AZ subnets. Keep aggregate desired, minimum, and maximum
capacity at exactly two `t3.medium` nodes. The default learning profile remains one node group
and is unchanged.

In the AWS HA Helm overlay, retain `topology.kubernetes.io/zone`, `maxSkew: 1`, and
`minDomains: 2`, but change `whenUnsatisfiable` to `ScheduleAnyway`. The scheduler will prefer
one replica per AZ while both are healthy and may place replacement stateless replicas in the
surviving AZ during the bounded node-loss drill. Keep both PodDisruptionBudgets at
`minAvailable: 1`.

T-1103 deliberately drains the node that does not host the single-AZ in-cluster PostgreSQL
pod. This proves stateless API/web resilience, not database HA. Multi-AZ database failover is
outside P11's approved scope and remains governed by ADR 0014.

## Consequences

The healthy P11.4 placement is deterministic and the two-node cost ceiling does not change.
There are two managed node-group resources to create and destroy instead of one. During an AZ
loss, topology skew is temporarily accepted so application availability wins; normal scheduling
still prefers balanced placement once both AZs are available.

The owner's technical-design acceptance permits opening a fresh bounded, alarmed P11.4 session
and generating the exact Terraform plan. It does not authorize `terraform apply`. Apply remains
blocked until that saved plan passes the runbook's cost, scope, persistence, and no-NAT checks
and the owner explicitly authorizes applying that exact plan inside the active session.

Rollback is to disable the opt-in variable and restore the AWS HA overlay's hard constraint; all
session resources are temporary and torn down the same day.
