# ADR 0018: Omit minDomains for soft topology spread

- Status: Accepted
- Date: 2026-08-18
- Supersedes: ADR 0017's requirement to combine `minDomains: 2` with `ScheduleAnyway`

## Context

The first P11.4 Helm install against EKS Kubernetes 1.34 failed atomically before creating the
application workloads. API validation rejects `minDomains` unless `whenUnsatisfiable` is
`DoNotSchedule`. ADR 0017's proposed combination of `minDomains: 2` and `ScheduleAnyway` is
therefore not a valid Kubernetes topology spread constraint.

## Decision

Keep ADR 0017's two AZ-pinned one-node groups, `topology.kubernetes.io/zone`, `maxSkew: 1`, soft
`ScheduleAnyway` behavior, and PDBs. Omit `minDomains` from the AWS HA overlay. The chart emits
`minDomains` only for hard `DoNotSchedule` constraints, preserving the already-proven local HA
profile while allowing the AWS profile to prefer cross-AZ placement and recover into one AZ.

## Consequences

The AWS profile is accepted by Kubernetes 1.34 and retains the intended availability tradeoff.
Healthy placement must still be verified across both AZs before fault injection because soft
spread is a preference, not an admission guarantee. Rollback is to restore the hard
`DoNotSchedule` profile, which also restores valid `minDomains: 2` rendering.
