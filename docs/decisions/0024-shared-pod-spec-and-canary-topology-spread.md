# ADR 0024: One shared pod spec; the canary inherits soft topology spread

- Status: Accepted
- Date: 2026-09-03
- Relates to: ADR 0017 (AZ-pinned node groups, soft failover spread), ADR 0018 (omit
  `minDomains` for soft spread), ADR 0023 (controller-native weighted canary)

## Context

`charts/bedoux/templates/canary.yaml` was authored by copying the stable pod specs from
`api.yaml` and `web.yaml` and changing the image source. Of the 73-line API canary pod spec, only
three lines genuinely differed: two image references and one `imagePullPolicy`.

The copy silently omitted the `topologySpreadConstraints` block. On the HA profile the stable
`api` and `web` Deployments therefore carried soft cross-AZ spread and the `api-canary` and
`web-canary` Deployments did not. Nothing recorded this as a choice, no test covered it, and it
was found only by rendering the HA profile with a canary staged during the post-P14 architecture
audit.

Two questions follow, and they are separable:

1. Should the two pod specs remain independent copies?
2. Should a one-replica canary carry soft topology spread at all?

## Decision

**One shared pod spec.** `bedoux.apiPodSpec` and `bedoux.webPodSpec` in `_helpers.tpl` render the
pod spec for both the stable and the canary Deployment. Everything that genuinely varies — pod
label and topology selector, image map, ConfigMap name, optional command override — is a
parameter. Everything else is shared by construction, so the two sides cannot drift again without
a deliberate parameter change.

**The canary inherits soft topology spread.** The canary Deployments now render the same
`topologySpreadConstraints` as their stable counterparts, with the label selector scoped to the
canary's own pods.

This is honestly a no-op at today's settings, and is adopted for a different reason than runtime
behaviour. `canary.replicas` is `1`, the constraint's `labelSelector` matches only that
Deployment's own pods, and `whenUnsatisfiable` is `ScheduleAnyway` per ADR 0018 — a single pod has
no siblings to balance against, so the scheduler behaves identically with or without the block.
The value is that the gap cannot reopen silently: if `canary.replicas` is ever raised, spread
applies automatically instead of being absent for the same copy-paste reason that caused this ADR.

The rejected alternative was to record the omission as intentional and leave the canary unspread.
That is defensible for a short-lived, bounded canary, but it leaves a trap — the omission looks
identical to an oversight, which is exactly how it was produced.

## Consequences

Stable and canary rendering is now provably equivalent except for the parameterised differences;
`canary.yaml` drops from 197 lines to 87 and the ~70 duplicated lines are gone. Verification was a
golden-render comparison across all 13 profiles: ten are byte-identical to the pre-refactor
output, the two non-HA canary profiles gain only YAML comments that the stable side already
carried, and the HA-canary profile gains the intended spread blocks — no other semantic change.
Only the three canary-enabled profiles differ at all.

`scripts/test_helm_render.py`'s M1 placeholder contract
`ha-canary-topology-divergence-pending-m2`, which pinned the divergence in place, is replaced by
`ha-canary-inherits-topology-spread`, which asserts the decision recorded here.

Runtime behaviour on the HA profile is unchanged at `canary.replicas: 1`. The canary still has no
PodDisruptionBudget, which remains correct for a single short-lived pod that the rollout script
removes itself; that is not revisited here. Rollback is to restore the two independent templates,
which also restores the divergence this ADR closes.

## Correction (2026-09-03, post-merge review of PR #70)

This record originally said **nine** profiles were byte-identical. The correct figure is **ten**:
`aws-cleanup` sets `canary.enabled=false` and is unchanged, so only the three canary-enabled
profiles differ out of thirteen. Found by the reviewer of PR #70, who re-rendered every profile
independently rather than trusting the reported figure, and confirmed by re-deriving the counts
against `521f3a3`.

The decision this ADR records is unchanged, and the load-bearing evidence — **14 non-comment
changed lines, all of them the two intended seven-line `topologySpreadConstraints` blocks** — was
exact and remains so. The same miscount also reached `docs/PROGRESS.md` (corrected) and the commit
message of `d9fde03`, which is immutable and still reads "nine".
