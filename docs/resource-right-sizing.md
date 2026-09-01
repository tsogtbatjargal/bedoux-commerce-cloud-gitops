# Resource right-sizing evidence

## Scope

P14.1 revisits the Helm CPU and memory requests/limits using measurements retained from the
P11-P13 work. It changes only a value supported by quantitative evidence. A healthy rollout or
absence of an out-of-memory event is not treated as a memory measurement.

The chart remains a bounded learning profile, not a production capacity recommendation. HPA
maximums and node ceilings remain unchanged.

## Recorded observations

The quantitative source is the real Metrics Server sample recorded in the P11.1/T-1101 entry of
`docs/PROGRESS.md`. Kubernetes HPA CPU utilization is usage divided by CPU request, averaged over
the target pods. Applying the then-current requests gives:

| Workload/state | Recorded utilization | Request | Derived CPU use |
|---|---:|---:|---:|
| API, active load before scale-out | 458% | 50m | about 229m |
| API, settled idle | 6% | 50m | about 3m |
| Web, active load before scale-out | 80% | 25m | about 20m |
| Web, settled idle | 4% | 25m | about 1m |

The derivation is `request × utilization / 100`; values are approximate because the HPA reports
rounded utilization. P11.3 and P11.4 add real workload outcomes: the API and web reached their
bounded replica ceilings under load, the final live node-loss run served 33,507/33,507 successful
requests, and its p95 was 155.35 ms. P12 and P13 add healthy rollout, readiness, and public-traffic
evidence, but they did not retain CPU or memory samples. Those outcomes corroborate operability;
they are not substituted for missing resource measurements.

## Decisions

| Workload/resource | Before | P14.1 | Reason |
|---|---:|---:|---|
| API CPU request | 50m | 50m | Retain. It reserves more than the measured idle use while making the 60% HPA target trigger near 30m, well before the measured load peak. |
| API CPU limit | 250m | 500m | Increase. The measured 229m sample used about 92% of the old ceiling; 500m leaves roughly 2.2x measured-peak headroom and avoids making the observed peak the throttle boundary. |
| API memory request/limit | 64Mi / 256Mi | unchanged | No retained P11-P13 memory sample supports a reduction or increase. |
| Web CPU request/limit | 25m / 100m | unchanged | The request covered the measured 20m load sample; the limit was five times that sample. |
| Web memory request/limit | 32Mi / 64Mi | unchanged | No retained P11-P13 memory sample supports a change. |
| PostgreSQL CPU and memory | 100m / 500m; 128Mi / 256Mi | unchanged | P11-P13 retained no PostgreSQL resource sample. |

The API limit change also applies to `api-canary`, which consumes the stable API resource block.
It does not change Kubernetes scheduling cost because CPU limits are not reservations and the API
request remains 50m. At the maximum three API and three web replicas plus in-cluster PostgreSQL,
declared CPU requests remain 325m in total.

## Verification and rollback

T-1401 requires the base and AWS Helm profiles to render the exact reviewed values and the canary
to inherit them. PR validation asserts that contract in addition to the existing Helm lint/profile
renders.

Rollback is one value: restore `api.resources.limits.cpu` to `250m`. A later session may revisit
memory only after retaining `kubectl top pods --containers` or equivalent Container Insights
idle and bounded-load samples; it must not infer memory sizing from readiness alone.
