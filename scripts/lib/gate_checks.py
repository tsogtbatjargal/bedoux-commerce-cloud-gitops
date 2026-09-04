#!/usr/bin/env python3
"""M4: typed diagnostics for the P12/P13 AWS/Kubernetes gates.

Every check here previously lived as an inline ``python -c '...' 2>/dev/null || return 1``
inside a bash gate script, most of them inside a polling loop with a multi-minute deadline
(``p13-alb-reconciliation-gate.sh``). Suppressing stderr meant a malformed AWS response, a
missing JSON key, or a Python exception was indistinguishable from the ALB simply not having
reconciled yet — the operator waited out the full deadline for a timeout that explained
nothing.

This module keeps every check's logic unchanged and gives it two distinct outcomes instead
of one:

* :class:`NotReady` — the condition is false in a way that is *expected* while polling (the
  ALB hasn't reconciled, targets aren't healthy yet, a Deployment isn't available yet). Exits
  1. Prints nothing, matching the silent-retry behaviour callers already have.
* :class:`HarnessError` — anything else: malformed JSON, a missing key that should always be
  present, a tool that returned an unexpected shape, a genuine invariant violation. Exits 2
  and prints a diagnostic naming the check and the problem. A caller must never treat this the
  same as "not yet" — it means the check itself could not be evaluated, and continuing to poll
  would hide the problem for the entire timeout.

Standard library only. Each subcommand reads one JSON document from stdin (except
``error-rate`` and ``count-probe-statuses``, documented below) and any parameters from CLI
flags. See ``scripts/test_gate_checks.py`` for fixture tests of every check, and
``docs/decisions/`` for the ADR recording this split (M4).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections.abc import Callable


class NotReady(Exception):
    """The condition is false in an expected, poll-again way. Exit 1, silent."""


class HarnessError(Exception):
    """The check could not be evaluated, or a real invariant was violated. Exit 2, diagnosed."""


# --------------------------------------------------------------------------------------
# Checks — each takes already-parsed JSON (or primitives) and either returns a value,
# returns None, or raises NotReady / HarnessError. No I/O here; main() owns stdin/argv/exit.
# --------------------------------------------------------------------------------------


def target_group_arns(tgb: dict, *, stable_service: str, canary_service: str, mode: str) -> list[str]:
    """From TargetGroupBindings, the stable ARN and (if the mode requires one) canary ARN."""
    items = tgb.get("items")
    if items is None:
        raise HarnessError("TargetGroupBindings list response has no 'items' key")
    stable = [
        item["spec"]["targetGroupARN"]
        for item in items
        if item.get("spec", {}).get("serviceRef", {}).get("name") == stable_service
    ]
    canary = [
        item["spec"]["targetGroupARN"]
        for item in items
        if item.get("spec", {}).get("serviceRef", {}).get("name") == canary_service
    ]
    canary_required = mode in {"staged", "promotion"}
    if len(stable) != 1:
        raise NotReady(f"expected exactly one stable target group, found {len(stable)}")
    if canary_required and len(canary) != 1:
        raise NotReady(f"expected exactly one canary target group, found {len(canary)}")
    if not canary_required and canary:
        raise NotReady(f"expected no canary target group in mode '{mode}', found {len(canary)}")
    return [stable[0], canary[0]] if canary_required else [stable[0]]


def service_target_group_arn(bindings: dict, *, service: str) -> str:
    """The one TargetGroupBinding ARN for a given Service name."""
    items = bindings.get("items")
    if items is None:
        raise HarnessError("TargetGroupBindings list response has no 'items' key")
    matches = [
        item["spec"]["targetGroupARN"]
        for item in items
        if item.get("spec", {}).get("serviceRef", {}).get("name") == service
    ]
    if len(matches) != 1:
        raise NotReady(f"expected exactly one target group for service '{service}', found {len(matches)}")
    return matches[0]


def alb_arn(load_balancers: dict, *, hostname: str) -> str:
    """The ARN of the one active application load balancer matching a DNS hostname."""
    lbs = load_balancers.get("LoadBalancers")
    if lbs is None:
        raise HarnessError("describe-load-balancers response has no 'LoadBalancers' key")
    matches = [
        lb
        for lb in lbs
        if lb.get("DNSName") == hostname
        and lb.get("Type") == "application"
        and lb.get("State", {}).get("Code") == "active"
    ]
    if len(matches) != 1:
        raise NotReady(f"expected exactly one active ALB matching the hostname, found {len(matches)}")
    arn = matches[0].get("LoadBalancerArn")
    if not arn:
        raise HarnessError("matched load balancer has no 'LoadBalancerArn'")
    return arn


def listener_arns(listeners: dict) -> list[str]:
    """Every listener ARN on the load balancer. Cardinality is the caller's concern."""
    items = listeners.get("Listeners")
    if items is None:
        raise HarnessError("describe-listeners response has no 'Listeners' key")
    try:
        return [listener["ListenerArn"] for listener in items]
    except KeyError as exc:
        raise HarnessError(f"a listener is missing 'ListenerArn': {exc}") from exc


def rule_weight_matches(
    rules: dict, *, stable_arn: str, canary_arn: str | None, weight: int, mode: str
) -> None:
    """Raises NotReady unless one rule's forward action matches the expected weight split."""
    rule_list = rules.get("Rules")
    if rule_list is None:
        raise HarnessError("describe-rules response has no 'Rules' key")
    expected = {stable_arn: 100 - weight}
    if mode != "cleanup":
        if canary_arn is None:
            raise HarnessError(f"mode '{mode}' requires a canary target group ARN")
        expected[canary_arn] = weight

    for rule in rule_list:
        for action in rule.get("Actions", []):
            if action.get("Type") != "forward":
                continue
            groups = action.get("ForwardConfig", {}).get("TargetGroups", [])
            if mode == "cleanup":
                direct = action.get("TargetGroupArn")
                if (
                    len(groups) == 1
                    and groups[0].get("TargetGroupArn") == stable_arn
                    and isinstance(groups[0].get("Weight"), int)
                    and groups[0]["Weight"] > 0
                    and direct in {None, stable_arn}
                ):
                    return
                continue
            actual = {group.get("TargetGroupArn"): group.get("Weight") for group in groups}
            if actual == expected:
                return
    raise NotReady(f"no listener rule yet matches the expected forward split for mode '{mode}'")


def deregistration_delay_matches(attributes: dict, *, expected_seconds: int) -> None:
    """Raises NotReady unless the target group's deregistration delay attribute matches."""
    attribute_list = attributes.get("Attributes")
    if attribute_list is None:
        raise HarnessError("describe-target-group-attributes response has no 'Attributes' key")
    values = {item.get("Key"): item.get("Value") for item in attribute_list}
    actual = values.get("deregistration_delay.timeout_seconds")
    if actual != str(expected_seconds):
        raise NotReady(
            f"deregistration_delay.timeout_seconds is {actual!r}, expected {expected_seconds!r}"
        )


def target_health_all_healthy(health: dict) -> None:
    """Raises NotReady unless every registered target reports state 'healthy'."""
    descriptions = health.get("TargetHealthDescriptions")
    if descriptions is None:
        raise HarnessError("describe-target-health response has no 'TargetHealthDescriptions' key")
    states = [item.get("TargetHealth", {}).get("State") for item in descriptions]
    if not states:
        raise NotReady("target group has no registered targets yet")
    unhealthy = [state for state in states if state != "healthy"]
    if unhealthy:
        raise NotReady(f"{len(unhealthy)} of {len(states)} targets are not yet healthy: {unhealthy}")


def alb_weight_matches(action: dict, *, weight: int) -> None:
    """Raises HarnessError unless the ALB annotation's forward weights match exactly.

    Unlike the reconciliation gate's rule-weight-matches, this runs once, after the ALB
    reconciliation gate has already required this exact split — so a mismatch here means an
    invariant the caller believed was already true is false, not an expected transient state.
    """
    try:
        groups = {item["serviceName"]: item["weight"] for item in action["forwardConfig"]["targetGroups"]}
    except (KeyError, TypeError) as exc:
        raise HarnessError(f"ALB forward-action annotation has an unexpected shape: {exc}") from exc
    expected = {"web": 100 - weight, "web-canary": weight}
    if groups != expected:
        raise HarnessError(f"ALB forward weights are {groups}, expected {expected}")


def cleanup_action_is_stable_only(action: dict) -> None:
    """Raises HarnessError unless the ALB annotation forwards 100% to the stable Service."""
    try:
        groups = {item["serviceName"]: item["weight"] for item in action["forwardConfig"]["targetGroups"]}
    except (KeyError, TypeError) as exc:
        raise HarnessError(f"ALB forward-action annotation has an unexpected shape: {exc}") from exc
    if groups != {"web": 100}:
        raise HarnessError(f"cleanup forward action is {groups}, expected stable-only {{'web': 100}}")


def pod_readiness_gate(pods: dict) -> int:
    """Count of active pods, each Running/Ready with a True ALB target-health readiness gate."""
    items = pods.get("items")
    if items is None:
        raise HarnessError("pod list response has no 'items' key")
    active = [item for item in items if not item.get("metadata", {}).get("deletionTimestamp")]
    if not active:
        raise NotReady("no active (non-terminating) pods match the selector yet")

    prefix = "target-health.elbv2.k8s.aws/"
    for item in active:
        if item.get("status", {}).get("phase") != "Running":
            raise NotReady("a pod is not yet Running")
        gates = [
            gate.get("conditionType")
            for gate in item.get("spec", {}).get("readinessGates", [])
            if gate.get("conditionType", "").startswith(prefix)
        ]
        if not gates:
            raise NotReady("a pod has no ALB target-health readiness gate yet")
        conditions = {c.get("type"): c.get("status") for c in item.get("status", {}).get("conditions", [])}
        if conditions.get("Ready") != "True" or any(conditions.get(gate) != "True" for gate in gates):
            raise NotReady("a pod's readiness gate is not yet True")
    return len(active)


def health_response_exact(response: dict, *, expected: dict) -> None:
    """Raises HarnessError unless /health's response equals the given dict exactly.

    Unlike health_status_ok (which only checks status, and tolerates any other keys), this
    is a strict equality check -- used only for the live P12 TLS proof, where any drift in
    the health response shape (a new field, orders_enabled left true) should fail loudly
    rather than pass unnoticed.
    """
    if response != expected:
        raise HarnessError(f"/health response was {response}, expected exactly {expected}")


def health_status_ok(response: dict, *, orders_enabled: bool | None = None) -> None:
    """Raises HarnessError unless /health reports status 'ok' (and, if given, orders_enabled)."""
    if response.get("status") != "ok":
        raise HarnessError(f"/health did not report status 'ok': {response}")
    if orders_enabled is not None and response.get("orders_enabled") != orders_enabled:
        raise HarnessError(
            f"/health orders_enabled was {response.get('orders_enabled')!r}, expected {orders_enabled!r}"
        )


def catalog_nonempty(products: list) -> None:
    """Raises HarnessError unless the product catalog response is a non-empty list."""
    if not isinstance(products, list) or len(products) < 1:
        raise HarnessError(f"expected a non-empty product list, got: {products!r}")


def count_probe_statuses(lines: list[str], *, marker: str) -> tuple[int, int]:
    """(hits, http_errors) for access-log lines containing marker, by trailing status code."""
    hits = errors = 0
    for line in lines:
        if marker not in line:
            continue
        hits += 1
        match = re.search(r"\"\s+(\d{3})\s+", line)
        if match and int(match.group(1)) >= 400:
            errors += 1
    return hits, errors


def error_rate(errors: int, attempts: int) -> str:
    """Formats errors/attempts to 4 decimal places, as the callers already print it."""
    if attempts <= 0:
        raise HarnessError(f"attempts must be positive, got {attempts}")
    return f"{errors / attempts:.4f}"


# --------------------------------------------------------------------------------------
# CLI dispatch
# --------------------------------------------------------------------------------------


def _read_stdin_json() -> object:
    try:
        return json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        raise HarnessError(f"stdin was not valid JSON: {exc}") from exc


def _cmd_target_group_arns(args: argparse.Namespace) -> None:
    for line in target_group_arns(
        _read_stdin_json(), stable_service=args.stable_service, canary_service=args.canary_service, mode=args.mode
    ):
        print(line)


def _cmd_service_target_group_arn(args: argparse.Namespace) -> None:
    print(service_target_group_arn(_read_stdin_json(), service=args.service))


def _cmd_alb_arn(args: argparse.Namespace) -> None:
    print(alb_arn(_read_stdin_json(), hostname=args.hostname))


def _cmd_listener_arns(_args: argparse.Namespace) -> None:
    for arn in listener_arns(_read_stdin_json()):
        print(arn)


def _cmd_rule_weight_matches(args: argparse.Namespace) -> None:
    rule_weight_matches(
        _read_stdin_json(),
        stable_arn=args.stable,
        canary_arn=args.canary,
        weight=args.weight,
        mode=args.mode,
    )


def _cmd_deregistration_delay(args: argparse.Namespace) -> None:
    deregistration_delay_matches(_read_stdin_json(), expected_seconds=args.expected_seconds)


def _cmd_target_health(_args: argparse.Namespace) -> None:
    target_health_all_healthy(_read_stdin_json())


def _cmd_alb_weight_matches(args: argparse.Namespace) -> None:
    alb_weight_matches(_read_stdin_json(), weight=args.weight)


def _cmd_cleanup_action_is_stable_only(_args: argparse.Namespace) -> None:
    cleanup_action_is_stable_only(_read_stdin_json())


def _cmd_pod_readiness_gate(_args: argparse.Namespace) -> None:
    print(pod_readiness_gate(_read_stdin_json()))


def _cmd_health_response_exact(args: argparse.Namespace) -> None:
    try:
        expected = json.loads(args.expected_json)
    except json.JSONDecodeError as exc:
        raise HarnessError(f"--expected-json was not valid JSON: {exc}") from exc
    health_response_exact(_read_stdin_json(), expected=expected)


def _cmd_health_status_ok(args: argparse.Namespace) -> None:
    orders_enabled = {"true": True, "false": False, "": None}[args.orders_enabled or ""]
    health_status_ok(_read_stdin_json(), orders_enabled=orders_enabled)


def _cmd_catalog_nonempty(_args: argparse.Namespace) -> None:
    catalog_nonempty(_read_stdin_json())


def _cmd_count_probe_statuses(args: argparse.Namespace) -> None:
    hits, errors = count_probe_statuses(sys.stdin.read().splitlines(), marker=args.marker)
    print(hits, errors)


def _cmd_error_rate(args: argparse.Namespace) -> None:
    print(error_rate(args.errors, args.attempts))


_COMMANDS: dict[str, tuple[Callable[[argparse.Namespace], None], Callable[[argparse.ArgumentParser], None]]] = {}


def _register(name: str, handler: Callable, add_args: Callable[[argparse.ArgumentParser], None]) -> None:
    _COMMANDS[name] = (handler, add_args)


_register(
    "target-group-arns",
    _cmd_target_group_arns,
    lambda p: (
        p.add_argument("--stable-service", required=True),
        p.add_argument("--canary-service", required=True),
        p.add_argument("--mode", required=True),
    ),
)
_register("service-target-group-arn", _cmd_service_target_group_arn, lambda p: p.add_argument("--service", required=True))
_register("alb-arn", _cmd_alb_arn, lambda p: p.add_argument("--hostname", required=True))
_register("listener-arns", _cmd_listener_arns, lambda p: None)
_register(
    "rule-weight-matches",
    _cmd_rule_weight_matches,
    lambda p: (
        p.add_argument("--stable", required=True),
        p.add_argument("--canary", default=None),
        p.add_argument("--weight", type=int, required=True),
        p.add_argument("--mode", required=True),
    ),
)
_register(
    "deregistration-delay",
    _cmd_deregistration_delay,
    lambda p: p.add_argument("--expected-seconds", type=int, required=True),
)
_register("target-health", _cmd_target_health, lambda p: None)
_register("alb-weight-matches", _cmd_alb_weight_matches, lambda p: p.add_argument("--weight", type=int, required=True))
_register("cleanup-action-is-stable-only", _cmd_cleanup_action_is_stable_only, lambda p: None)
_register("pod-readiness-gate", _cmd_pod_readiness_gate, lambda p: None)
_register(
    "health-status-ok",
    _cmd_health_status_ok,
    lambda p: p.add_argument("--orders-enabled", choices=["true", "false"], default=None),
)
_register(
    "health-response-exact",
    _cmd_health_response_exact,
    lambda p: p.add_argument("--expected-json", required=True),
)
_register("catalog-nonempty", _cmd_catalog_nonempty, lambda p: None)
_register("count-probe-statuses", _cmd_count_probe_statuses, lambda p: p.add_argument("--marker", required=True))
_register(
    "error-rate",
    _cmd_error_rate,
    lambda p: (p.add_argument("errors", type=int), p.add_argument("attempts", type=int)),
)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="gate_checks", description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for name, (_handler, add_args) in _COMMANDS.items():
        subparser = subparsers.add_parser(name)
        add_args(subparser)

    args = parser.parse_args(argv)
    handler, _add_args = _COMMANDS[args.command]

    try:
        handler(args)
    except NotReady:
        return 1
    except HarnessError as exc:
        print(f"HARNESS ERROR [{args.command}]: {exc}", file=sys.stderr)
        return 2
    except Exception as exc:  # noqa: BLE001 - deliberately broad: any other exception is a harness error
        print(f"HARNESS ERROR [{args.command}]: unexpected {type(exc).__name__}: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
