# ADR 0019: Bound ALB draining and require target-health readiness gates

- Status: Accepted
- Date: 2026-08-18
- Accepted by owner: 2026-08-18 (technical design; live AWS retry remains separately gated)

## Context

The first live T-1103 attempt maintained a healthy two-AZ baseline and recovered the stateless
replicas on the surviving node, but 115 of 30,265 public catalog requests failed during the drain
transition. The request count stopped advancing for about 30 seconds. The chart had no preStop
hook or explicit termination grace period, used the ALB target group's default deregistration
behavior, and did not inject AWS target-health readiness gates. The recorded k6 summary did not
include p99 or per-failure status diagnostics, so this timing is evidence of a termination-path
gap but is not enough to claim one proven root cause.

The ALB targets web pod IPs directly. Kubernetes begins pod shutdown and Service endpoint
withdrawal concurrently, while the AWS Load Balancer Controller reconciles target registration
and deregistration asynchronously. A terminating target must therefore remain alive long enough
for ALB to stop routing and drain in-flight connections, and a replacement web pod must not count
as Ready before ALB reports its target healthy.

## Decision

For the opt-in AWS HA overlay only, set the ALB target-group deregistration delay to 30 seconds,
hold both web and API containers in a 45-second preStop hook, and set their pod termination grace
period to 60 seconds. The 15-second difference is a bounded reconciliation margin; the default
local/kind profile retains no preStop delay and its existing 30-second grace period.

Label the Bedoux namespace for AWS Load Balancer Controller pod-readiness-gate injection before
application pods exist. Bootstrap the Helm release with zero API/web replicas and disabled HPAs,
wait for the controller-created web TargetGroupBinding, then perform the normal Helm upgrade.
This ordering ensures new web pods receive a `target-health.elbv2.k8s.aws/...` readiness gate.
The P11.4 inspect helper must refuse a live fault unless the runtime termination values, Ingress
target-group attribute, and readiness gates all match this contract.

Retain the exact-zero k6 thresholds and add p99 plus timestamped status/error diagnostics. These
changes improve the next test's evidence but do not relax T-1103.

## Consequences

A voluntary drain takes at least 45 seconds for affected application pods, while staying within
the existing five-minute drain timeout. Direct ALB targets remain alive longer than the bounded
target deregistration interval; API pods receive the same hold for in-cluster EndpointSlice and
in-flight proxy-request draining. Rollouts require a two-stage initial install in AWS, but later
upgrades and recovery restarts use the injected target-health gate normally.

This is a correction hypothesis, not successful T-1103 evidence. Acceptance permits a fresh
alarmed session and exact plan review; it does not authorize Terraform apply or the drain. The
decision is validated only if a later bounded live retry records zero failed requests and clean
recovery/teardown. Rollback removes the AWS HA overrides and namespace label; local profiles are
unchanged.

## References

- [AWS Load Balancer Controller pod readiness gates](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/pod_readiness_gate/)
- [Kubernetes pod termination flow](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-termination-flow)
- [AWS ALB target deregistration delay](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/edit-target-group-attributes.html#modify-target-group-health-settings)
