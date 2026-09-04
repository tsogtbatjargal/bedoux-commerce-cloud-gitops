#!/usr/bin/env python3
"""M4: fixture tests for scripts/lib/gate_checks.py.

Every check gets three cases: a JSON shape from the repo's own mocks that should pass, one
that is legitimately "not yet" (NotReady, exit 1, silent), and one that is malformed or
violates an invariant (HarnessError, exit 2, diagnosed). Run with
``python3 scripts/test_gate_checks.py``.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import gate_checks as gc  # noqa: E402

FAILURES: list[str] = []


def check(description: str, fn, *args, **kwargs) -> None:
    try:
        fn(*args, **kwargs)
    except Exception as exc:  # noqa: BLE001
        FAILURES.append(f"  {description}: unexpected {type(exc).__name__}: {exc}")
        print(f"  FAIL      {description}")
    else:
        print(f"  ok        {description}")


def expect_not_ready(description: str, fn, *args, **kwargs) -> None:
    try:
        fn(*args, **kwargs)
    except gc.NotReady:
        print(f"  ok        {description}")
        return
    except Exception as exc:  # noqa: BLE001
        FAILURES.append(f"  {description}: expected NotReady, got {type(exc).__name__}: {exc}")
        print(f"  FAIL      {description}")
        return
    FAILURES.append(f"  {description}: expected NotReady, nothing was raised")
    print(f"  FAIL      {description}")


def expect_harness_error(description: str, fn, *args, **kwargs) -> None:
    try:
        fn(*args, **kwargs)
    except gc.HarnessError:
        print(f"  ok        {description}")
        return
    except Exception as exc:  # noqa: BLE001
        FAILURES.append(f"  {description}: expected HarnessError, got {type(exc).__name__}: {exc}")
        print(f"  FAIL      {description}")
        return
    FAILURES.append(f"  {description}: expected HarnessError, nothing was raised")
    print(f"  FAIL      {description}")


# --------------------------------------------------------------------------------------
# target_group_arns / service_target_group_arn — fixtures match
# scripts/test-p13-canary-regression-rollback.sh's kubectl mock shape.
# --------------------------------------------------------------------------------------

TGB_TWO_BOUND = {
    "items": [
        {"spec": {"serviceRef": {"name": "web"}, "targetGroupARN": "arn:stable"}},
        {"spec": {"serviceRef": {"name": "web-canary"}, "targetGroupARN": "arn:canary"}},
    ]
}
TGB_ONE_BOUND = {"items": [{"spec": {"serviceRef": {"name": "web"}, "targetGroupARN": "arn:stable"}}]}
TGB_EMPTY = {"items": []}

print("target_group_arns:")
check(
    "staged mode with both bound returns [stable, canary]",
    lambda: (
        result := gc.target_group_arns(TGB_TWO_BOUND, stable_service="web", canary_service="web-canary", mode="staged"),
        (_ for _ in ()).throw(AssertionError(result)) if result != ["arn:stable", "arn:canary"] else None,
    ),
)
check(
    "cleanup mode with only stable bound returns [stable]",
    lambda: (
        result := gc.target_group_arns(TGB_ONE_BOUND, stable_service="web", canary_service="web-canary", mode="cleanup"),
        (_ for _ in ()).throw(AssertionError(result)) if result != ["arn:stable"] else None,
    ),
)
expect_not_ready(
    "staged mode with no bindings yet is NotReady",
    gc.target_group_arns, TGB_EMPTY, stable_service="web", canary_service="web-canary", mode="staged",
)
expect_not_ready(
    "cleanup mode with a leftover canary binding is NotReady",
    gc.target_group_arns, TGB_TWO_BOUND, stable_service="web", canary_service="web-canary", mode="cleanup",
)
expect_harness_error(
    "malformed TargetGroupBindings response is a HarnessError",
    gc.target_group_arns, {}, stable_service="web", canary_service="web-canary", mode="staged",
)

print("service_target_group_arn:")
check("exactly one match returns the ARN", lambda: gc.service_target_group_arn(TGB_ONE_BOUND, service="web"))
expect_not_ready("no match is NotReady", gc.service_target_group_arn, TGB_EMPTY, service="web")
expect_not_ready(
    "two matches for one service is NotReady", gc.service_target_group_arn, TGB_TWO_BOUND, service="web-canary-and-web"
)

# --------------------------------------------------------------------------------------
# alb_arn / listener_arns — fixtures match test-p13-alb-reconciliation-gate.sh's aws mock.
# --------------------------------------------------------------------------------------

LOAD_BALANCERS = {
    "LoadBalancers": [
        {
            "DNSName": "mock.ca-central-1.elb.amazonaws.com",
            "Type": "application",
            "State": {"Code": "active"},
            "LoadBalancerArn": "arn:lb",
        }
    ]
}
LISTENERS = {"Listeners": [{"ListenerArn": "arn:listener"}]}

print("alb_arn:")
check(
    "one active matching ALB returns its ARN",
    lambda: gc.alb_arn(LOAD_BALANCERS, hostname="mock.ca-central-1.elb.amazonaws.com"),
)
expect_not_ready(
    "no matching hostname is NotReady (ALB not yet provisioned)",
    gc.alb_arn, LOAD_BALANCERS, hostname="unknown.elb.amazonaws.com",
)
expect_harness_error("missing LoadBalancers key is a HarnessError", gc.alb_arn, {}, hostname="x")

print("listener_arns:")
check("returns each listener ARN", lambda: (
    (result := gc.listener_arns(LISTENERS)),
    (_ for _ in ()).throw(AssertionError(result)) if result != ["arn:listener"] else None,
))
expect_harness_error("missing Listeners key is a HarnessError", gc.listener_arns, {})
expect_harness_error(
    "a listener missing ListenerArn is a HarnessError", gc.listener_arns, {"Listeners": [{}]}
)

# --------------------------------------------------------------------------------------
# rule_weight_matches — fixtures are the exact MOCK_RULE_MODE shapes from
# scripts/test-p13-alb-reconciliation-gate.sh.
# --------------------------------------------------------------------------------------

RULES_STAGED_10 = {
    "Rules": [
        {
            "Actions": [
                {
                    "Type": "forward",
                    "ForwardConfig": {
                        "TargetGroups": [
                            {"TargetGroupArn": "arn:stable", "Weight": 90},
                            {"TargetGroupArn": "arn:canary", "Weight": 10},
                        ]
                    },
                }
            ]
        }
    ]
}
RULES_PROMOTION_100_0 = {
    "Rules": [
        {
            "Actions": [
                {
                    "Type": "forward",
                    "ForwardConfig": {
                        "TargetGroups": [
                            {"TargetGroupArn": "arn:stable", "Weight": 100},
                            {"TargetGroupArn": "arn:canary", "Weight": 0},
                        ]
                    },
                }
            ]
        }
    ]
}
RULES_CLEANUP_DECLARED = {
    "Rules": [
        {
            "Actions": [
                {
                    "Type": "forward",
                    "ForwardConfig": {"TargetGroups": [{"TargetGroupArn": "arn:stable", "Weight": 100}]},
                }
            ]
        }
    ]
}
RULES_CLEANUP_NORMALIZED = {
    "Rules": [
        {
            "Actions": [
                {
                    "Type": "forward",
                    "TargetGroupArn": "arn:stable",
                    "ForwardConfig": {"TargetGroups": [{"TargetGroupArn": "arn:stable", "Weight": 1}]},
                }
            ]
        }
    ]
}
RULES_CLEANUP_ZERO_WEIGHT = {
    "Rules": [
        {
            "Actions": [
                {
                    "Type": "forward",
                    "TargetGroupArn": "arn:stable",
                    "ForwardConfig": {"TargetGroups": [{"TargetGroupArn": "arn:stable", "Weight": 0}]},
                }
            ]
        }
    ]
}

print("rule_weight_matches:")
check(
    "staged 90/10 matches",
    gc.rule_weight_matches, RULES_STAGED_10, stable_arn="arn:stable", canary_arn="arn:canary", weight=10, mode="staged",
)
check(
    "promotion 100/0 matches",
    gc.rule_weight_matches, RULES_PROMOTION_100_0, stable_arn="arn:stable", canary_arn="arn:canary", weight=0, mode="promotion",
)
check(
    "cleanup with AWS-normalized non-zero weight matches",
    gc.rule_weight_matches, RULES_CLEANUP_NORMALIZED, stable_arn="arn:stable", canary_arn=None, weight=0, mode="cleanup",
)
check(
    "cleanup declared 100% matches",
    gc.rule_weight_matches, RULES_CLEANUP_DECLARED, stable_arn="arn:stable", canary_arn=None, weight=0, mode="cleanup",
)
expect_not_ready(
    "cleanup rule still reporting zero weight is NotReady",
    gc.rule_weight_matches, RULES_CLEANUP_ZERO_WEIGHT, stable_arn="arn:stable", canary_arn=None, weight=0, mode="cleanup",
)
expect_not_ready(
    "staged rule not yet showing the requested split is NotReady",
    gc.rule_weight_matches, RULES_STAGED_10, stable_arn="arn:stable", canary_arn="arn:canary", weight=25, mode="staged",
)
expect_harness_error(
    "cleanup mode with no canary ARN required but canary_arn missing when mode='staged' is a HarnessError",
    gc.rule_weight_matches, RULES_STAGED_10, stable_arn="arn:stable", canary_arn=None, weight=10, mode="staged",
)
expect_harness_error("missing Rules key is a HarnessError", gc.rule_weight_matches, {}, stable_arn="a", canary_arn="b", weight=1, mode="staged")

# --------------------------------------------------------------------------------------
# deregistration_delay_matches / target_health_all_healthy
# --------------------------------------------------------------------------------------

ATTRIBUTES_30S = {"Attributes": [{"Key": "deregistration_delay.timeout_seconds", "Value": "30"}]}
ATTRIBUTES_300S = {"Attributes": [{"Key": "deregistration_delay.timeout_seconds", "Value": "300"}]}
HEALTH_ALL_HEALTHY = {"TargetHealthDescriptions": [{"TargetHealth": {"State": "healthy"}}]}
HEALTH_ONE_UNHEALTHY = {
    "TargetHealthDescriptions": [
        {"TargetHealth": {"State": "healthy"}},
        {"TargetHealth": {"State": "unhealthy"}},
    ]
}
HEALTH_EMPTY = {"TargetHealthDescriptions": []}

print("deregistration_delay_matches:")
check("30s matches 30s", gc.deregistration_delay_matches, ATTRIBUTES_30S, expected_seconds=30)
expect_not_ready("300s does not match 30s (not yet applied)", gc.deregistration_delay_matches, ATTRIBUTES_300S, expected_seconds=30)
expect_harness_error("missing Attributes key is a HarnessError", gc.deregistration_delay_matches, {}, expected_seconds=30)

print("target_health_all_healthy:")
check("all healthy passes", gc.target_health_all_healthy, HEALTH_ALL_HEALTHY)
expect_not_ready("one unhealthy target is NotReady", gc.target_health_all_healthy, HEALTH_ONE_UNHEALTHY)
expect_not_ready("no registered targets yet is NotReady", gc.target_health_all_healthy, HEALTH_EMPTY)
expect_harness_error("missing TargetHealthDescriptions key is a HarnessError", gc.target_health_all_healthy, {})

# --------------------------------------------------------------------------------------
# alb_weight_matches / cleanup_action_is_stable_only — fixtures match the
# alb.ingress.kubernetes.io/actions.web annotation shape used by p13-canary-gate.sh
# and p13-canary-rollout.sh.
# --------------------------------------------------------------------------------------

ACTION_90_10 = {"forwardConfig": {"targetGroups": [{"serviceName": "web", "weight": 90}, {"serviceName": "web-canary", "weight": 10}]}}
ACTION_STABLE_100 = {"forwardConfig": {"targetGroups": [{"serviceName": "web", "weight": 100}]}}

print("alb_weight_matches:")
check("90/10 matches weight=10", gc.alb_weight_matches, ACTION_90_10, weight=10)
expect_harness_error("100/0 does not match weight=10 (post-gate invariant violated)", gc.alb_weight_matches, ACTION_STABLE_100, weight=10)
expect_harness_error("malformed action annotation is a HarnessError", gc.alb_weight_matches, {}, weight=10)

print("cleanup_action_is_stable_only:")
check("stable-only 100% passes", gc.cleanup_action_is_stable_only, ACTION_STABLE_100)
expect_harness_error("a lingering canary weight is a HarnessError", gc.cleanup_action_is_stable_only, ACTION_90_10)
expect_harness_error("malformed action annotation is a HarnessError", gc.cleanup_action_is_stable_only, {})

# --------------------------------------------------------------------------------------
# pod_readiness_gate — fixtures match test-p13-alb-pod-readiness-gate.sh's kubectl mock.
# --------------------------------------------------------------------------------------

POD_READY = {
    "items": [
        {
            "metadata": {"name": "web-new"},
            "spec": {"readinessGates": [{"conditionType": "target-health.elbv2.k8s.aws/mock"}]},
            "status": {
                "phase": "Running",
                "conditions": [
                    {"type": "Ready", "status": "True"},
                    {"type": "target-health.elbv2.k8s.aws/mock", "status": "True"},
                ],
            },
        },
        {
            "metadata": {"name": "web-old", "deletionTimestamp": "2026-08-27T00:00:00Z"},
            "spec": {},
            "status": {"phase": "Running", "conditions": []},
        },
    ]
}
POD_NOT_READY = {
    "items": [
        {
            "metadata": {"name": "web"},
            "spec": {"readinessGates": [{"conditionType": "target-health.elbv2.k8s.aws/mock"}]},
            "status": {
                "phase": "Running",
                "conditions": [
                    {"type": "Ready", "status": "False"},
                    {"type": "target-health.elbv2.k8s.aws/mock", "status": "False"},
                ],
            },
        }
    ]
}

print("pod_readiness_gate:")
check("ready pod excluding a terminating one counts 1", lambda: (
    (result := gc.pod_readiness_gate(POD_READY)),
    (_ for _ in ()).throw(AssertionError(result)) if result != 1 else None,
))
expect_not_ready("a pod whose readiness gate is False is NotReady", gc.pod_readiness_gate, POD_NOT_READY)
expect_not_ready("no active pods at all is NotReady", gc.pod_readiness_gate, {"items": []})
expect_harness_error("missing items key is a HarnessError", gc.pod_readiness_gate, {})

# --------------------------------------------------------------------------------------
# health_status_ok / catalog_nonempty / count_probe_statuses / error_rate
# --------------------------------------------------------------------------------------

print("health_status_ok:")
check("status ok with no orders_enabled check passes", gc.health_status_ok, {"status": "ok"})
check(
    "status ok and orders_enabled=False matches",
    gc.health_status_ok, {"status": "ok", "orders_enabled": False}, orders_enabled=False,
)
expect_harness_error("status not ok is a HarnessError", gc.health_status_ok, {"status": "degraded"})
expect_harness_error(
    "orders_enabled mismatch is a HarnessError",
    gc.health_status_ok, {"status": "ok", "orders_enabled": True}, orders_enabled=False,
)

print("health_response_exact:")
check(
    "exact match passes",
    gc.health_response_exact, {"status": "ok", "orders_enabled": False}, expected={"status": "ok", "orders_enabled": False},
)
expect_harness_error(
    "an extra key is a HarnessError (unlike health_status_ok, which would tolerate it)",
    gc.health_response_exact, {"status": "ok", "orders_enabled": False, "extra": 1}, expected={"status": "ok", "orders_enabled": False},
)
expect_harness_error(
    "orders_enabled left true is a HarnessError",
    gc.health_response_exact, {"status": "ok", "orders_enabled": True}, expected={"status": "ok", "orders_enabled": False},
)

print("catalog_nonempty:")
check("non-empty list passes", gc.catalog_nonempty, [{"id": "1"}])
expect_harness_error("empty list is a HarnessError", gc.catalog_nonempty, [])
expect_harness_error("non-list is a HarnessError", gc.catalog_nonempty, {"not": "a list"})

print("count_probe_statuses:")
check("counts hits and 4xx/5xx as errors", lambda: (
    (result := gc.count_probe_statuses(
        [
            'GET /api/health?bedoux_direct_canary_probe=x-1 HTTP/1.1" 200 12',
            'GET /api/health?bedoux_direct_canary_probe=x-2 HTTP/1.1" 502 12',
            'GET /other HTTP/1.1" 200 12',
        ],
        marker="bedoux_direct_canary_probe=x-",
    )),
    (_ for _ in ()).throw(AssertionError(result)) if result != (2, 1) else None,
))

print("error_rate:")
check("formats to 4 decimals", lambda: (
    (result := gc.error_rate(1, 20)),
    (_ for _ in ()).throw(AssertionError(result)) if result != "0.0500" else None,
))
expect_harness_error("zero attempts is a HarnessError, not a ZeroDivisionError", gc.error_rate, 0, 0)


if FAILURES:
    print("\nFAILED:", file=sys.stderr)
    for failure in FAILURES:
        print(failure, file=sys.stderr)
    sys.exit(1)

print("\nOK — scripts/lib/gate_checks.py fixture tests passed.")
