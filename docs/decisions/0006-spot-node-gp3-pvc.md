# ADR 0006: Accept Spot-node interruption risk in P5; provision a real gp3 PVC via EBS CSI

- Status: Accepted
- Date: 2026-07-23

## Context

P5 stands up the first real EKS cluster, with in-cluster PostgreSQL (RDS is deferred to
P7, per ADR 0002). The learning profile uses one small managed Spot worker node where
capacity permits (`docs/IMPLEMENTATION-PLAN.md`'s AWS learning profile). Spot capacity
can be reclaimed with two minutes' notice, which raises a real question for a stateful
Postgres pod: what happens to its data, and is it worth engineering around?

This decision was made in conversation on 2026-07-19 and deliberately held until P5
opened (see `docs/IMPLEMENTATION-PLAN.md`'s "Pending owner-approved decisions" #3),
rather than implemented early.

## Decision

Accept Spot-node interruption risk explicitly rather than silently. A node interruption
may end a P5 demo session outright — that is a known, accepted cost of using Spot
capacity in a $2-4/session learning budget, not an oversight.

Still provision **real EBS-backed storage**: a `StorageClass` named `gp3`
(`ebs.csi.aws.com` provisioner, `volumeBindingMode: WaitForFirstConsumer`) backed by the
Amazon EBS CSI driver EKS add-on, which needs its own IRSA role (same identity pattern —
IAM Roles for Service Accounts — as the S3 adapter decision in pending-decisions #2).
Postgres's `PersistentVolumeClaim` (`charts/bedoux/templates/postgres.yaml`) uses this
storage class in the AWS session profile, via `postgres.storageClassName=gp3` in a
`values-aws.yaml` overlay; the kind profile keeps `storageClassName: ""` (cluster
default) unchanged.

**Scope boundary — what this explicitly does NOT do:** no multi-node Postgres,
replication, or automated failover is engineered in P5. The PVC protects data across
*pod* replacement on the *same* node (a crashed/restarted Postgres pod reattaches its
EBS volume and keeps its data) — it does not protect against *node* loss, which is a
single point of failure by design in this phase. The point of provisioning real
EBS-backed storage here is the EKS storage/IAM setup itself (StorageClass, CSI driver,
IRSA) — a real platform-engineering skill worth demonstrating — not database
resilience, which is P7's job via managed RDS.

## Consequences

- P5 demonstrates a real EKS storage stack (CSI driver, IRSA, dynamic provisioning) —
  portfolio-relevant even though the workload it backs has no HA.
- A Spot interruption during a P5 session is an accepted, expected possible outcome —
  if it happens, the response is "restart the session," not "investigate a bug."
- Any dashboard, walkthrough, or write-up describing this phase (P9's evidence reel
  included) must not claim durability or high availability for in-cluster Postgres —
  that would violate `AGENTS.md`'s rule against claiming production traits the system
  hasn't had.
- Real Postgres HA/durability is deferred to P7 (managed Single-AZ RDS with backups),
  itself explicitly not multi-AZ either — full HA stays in the documented-only
  production profile.
