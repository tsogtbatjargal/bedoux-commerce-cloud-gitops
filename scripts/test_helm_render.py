#!/usr/bin/env python3
"""The Helm chart's render contracts, as one locally runnable module (M1, extended by M2).

Every assertion here previously lived as an anonymous ``grep``/``test`` line inside
``.github/workflows/pr-validation.yml``. That shell could not be run before pushing, and a
failure reported only a step exit code, so a canary assertion that could never pass once
reached review certified as passing (P14.1, commit 7c2676a).

This module keeps the same contracts and changes only how they are expressed:

* each profile is rendered **once** and cached, replacing 17 ``helm template`` invocations;
* every assertion is **named**, so a failure says which profile and which contract broke;
* a **fail-sensitivity** pass deliberately breaks the chart and requires the matching
  contract to reject it, so a vacuous assertion cannot pass unnoticed;
* stable and canary render from one shared pod-spec module (M2, ADR 0024), and a contract
  proves they stay equivalent apart from their parameters.

Standard library only, no AWS or Kubernetes access. Run it with ``make helm-test``.
"""

from __future__ import annotations

import difflib
import re
import shutil
import subprocess
import sys
import tempfile
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CHART_DIR = REPO_ROOT / "charts" / "bedoux"


class ContractError(AssertionError):
    """A render contract was violated. Names the profile, the contract, and the detail."""

    def __init__(self, profile: str, contract: str, detail: str) -> None:
        super().__init__(f"[{contract}] profile '{profile}': {detail}")
        self.profile = profile
        self.contract = contract
        self.detail = detail


class HarnessError(RuntimeError):
    """The check could not be evaluated at all — a missing tool or an unexpected failure.

    Deliberately distinct from ContractError: 'the chart is wrong' and 'I could not tell'
    must never collapse into the same signal.
    """


# --------------------------------------------------------------------------------------
# Profiles — the exact value-file and --set combinations the workflow used to render.
# --------------------------------------------------------------------------------------

_DIGEST = "sha256:" + "a" * 64
_CANDIDATE_DIGEST = "sha256:" + "b" * 64

PROFILES: dict[str, list[str]] = {
    "base": [],
    "base-migration-off": ["--set", "migration.enabled=false"],
    "base-digest": [
        "--set-string", f"api.image.digest={_DIGEST}",
        "--set-string", f"web.image.digest={_DIGEST}",
    ],
    "aws": ["-f", "values-aws.yaml"],
    "aws-dereg30": [
        "-f", "values-aws.yaml",
        "--set", "ingress.targetGroupDeregistrationDelaySeconds=30",
    ],
    "aws-tls": ["-f", "values-aws.yaml", "-f", "values-aws-tls.yaml"],
    "aws-rds": ["-f", "values-aws.yaml", "-f", "values-aws-rds.yaml"],
    "aws-ha": ["-f", "values-aws.yaml", "-f", "values-aws-ha.yaml"],
    "kind-ha": ["-f", "values-kind-ha.yaml"],
    "aws-canary": [
        "-f", "values-aws.yaml",
        "--set", "canary.enabled=true",
        "--set", "canary.weight=10",
        "--set-string", f"api.image.digest={_DIGEST}",
        "--set-string", f"web.image.digest={_DIGEST}",
        "--set-string", f"canary.api.image.digest={_CANDIDATE_DIGEST}",
        "--set-string", f"canary.web.image.digest={_CANDIDATE_DIGEST}",
    ],
    "aws-canary-regression": [
        "-f", "values-aws.yaml",
        "--set", "canary.enabled=true",
        "--set", "canary.weight=10",
        "--set", "canary.regressionMode=http-error",
    ],
    "aws-cleanup": [
        "-f", "values-aws.yaml",
        "--set", "canary.enabled=false",
        "--set", "migration.enabled=false",
    ],
    # The HA profile with a canary staged. See ha_canary_inherits_topology_spread (ADR 0024).
    "aws-ha-canary": [
        "-f", "values-aws.yaml",
        "-f", "values-aws-ha.yaml",
        "--set", "canary.enabled=true",
        "--set", "canary.weight=10",
    ],
}

# Profiles that must fail to render. Each one is a fail-closed guarantee.
FAIL_CLOSED_PROFILES: dict[str, list[str]] = {
    "tls-without-alb": ["--set", "ingress.tls.enabled=true"],
    "canary-unknown-regression-mode": [
        "--set", "canary.enabled=true",
        "--set", "canary.regressionMode=unknown",
    ],
    "canary-weight-over-ceiling": [
        "--set", "canary.enabled=true",
        "--set", "canary.weight=51",
    ],
}


class Renderer:
    """Renders a chart once per profile and caches the result."""

    def __init__(self, chart_dir: Path) -> None:
        self.chart_dir = chart_dir
        self._cache: dict[str, str] = {}

    def _helm(self, args: list[str]) -> subprocess.CompletedProcess[str]:
        try:
            return subprocess.run(
                ["helm", *args],
                capture_output=True,
                text=True,
                cwd=self.chart_dir.parent.parent,
            )
        except FileNotFoundError as exc:
            raise HarnessError("helm is not installed or not on PATH") from exc

    def _profile_args(self, profile: str) -> list[str]:
        args = PROFILES.get(profile)
        if args is None:
            raise HarnessError(f"unknown profile '{profile}'")
        # Value-file paths are relative to the chart so a mutated copy resolves its own files.
        resolved: list[str] = []
        expect_path = False
        for arg in args:
            if expect_path:
                resolved.append(str(self.chart_dir / arg))
                expect_path = False
            else:
                resolved.append(arg)
                expect_path = arg == "-f"
        return resolved

    def get(self, profile: str) -> "Rendered":
        if profile not in self._cache:
            result = self._helm(
                ["template", "bedoux", str(self.chart_dir), *self._profile_args(profile)]
            )
            if result.returncode != 0:
                raise ContractError(
                    profile, "profile-renders", f"helm template failed: {result.stderr.strip()}"
                )
            self._cache[profile] = result.stdout
        return Rendered(profile, self._cache[profile])

    def expect_render_failure(self, profile: str, contract: str) -> None:
        args = FAIL_CLOSED_PROFILES[profile]
        result = self._helm(["template", "bedoux", str(self.chart_dir), *args])
        if result.returncode == 0:
            raise ContractError(profile, contract, "render succeeded but must fail closed")

    def lint(self) -> None:
        result = self._helm(["lint", str(self.chart_dir)])
        if result.returncode != 0:
            raise ContractError("chart", "helm-lint", result.stdout.strip() or result.stderr.strip())


class Rendered:
    """One rendered profile, with named assertions over its text."""

    def __init__(self, profile: str, text: str) -> None:
        self.profile = profile
        self.text = text
        self.lines = text.splitlines()

    def contains(self, needle: str, contract: str) -> None:
        if needle not in self.text:
            raise ContractError(self.profile, contract, f"expected text is absent: {needle!r}")

    def excludes(self, needle: str, contract: str) -> None:
        if needle in self.text:
            raise ContractError(self.profile, contract, f"forbidden text is present: {needle!r}")

    def exact_lines(self, line: str, expected: int, contract: str) -> None:
        found = self.lines.count(line)
        if found != expected:
            raise ContractError(
                self.profile,
                contract,
                f"expected exactly {expected} line(s) {line!r}, found {found}",
            )

    def matching_lines(self, pattern: str, expected: int, contract: str) -> None:
        compiled = re.compile(pattern)
        found = sum(1 for line in self.lines if compiled.fullmatch(line))
        if found != expected:
            raise ContractError(
                self.profile,
                contract,
                f"expected exactly {expected} line(s) matching {pattern!r}, found {found}",
            )

    def excludes_pattern(self, pattern: str, contract: str) -> None:
        compiled = re.compile(pattern)
        for line in self.lines:
            if compiled.fullmatch(line):
                raise ContractError(
                    self.profile, contract, f"forbidden line present: {line.strip()!r}"
                )

    def pod_spec(self, deployment: str) -> str | None:
        """The rendered pod spec of one Deployment, as text, or None if absent."""
        for document in self.text.split("\n---\n"):
            lines = document.splitlines()
            if not any(line == "kind: Deployment" for line in lines):
                continue
            if not any(line == f"  name: {deployment}" for line in lines):
                continue
            for index, line in enumerate(lines):
                if line == "    spec:":  # pod spec inside template:
                    return "\n".join(lines[index + 1:])
        return None

    def deployments_with_topology_spread(self) -> set[str]:
        """Names of Deployments whose pod spec carries topologySpreadConstraints."""
        spread: set[str] = set()
        for document in self.text.split("\n---\n"):
            lines = document.splitlines()
            if not any(line == "kind: Deployment" for line in lines):
                continue
            name = next(
                (line[len("  name: "):] for line in lines if line.startswith("  name: ")), None
            )
            if name and any(line.strip() == "topologySpreadConstraints:" for line in lines):
                spread.add(name)
        return spread


# --------------------------------------------------------------------------------------
# Contracts
# --------------------------------------------------------------------------------------

CONTRACTS: list[tuple[str, Callable[[Renderer], None]]] = []


def contract(name: str) -> Callable[[Callable[[Renderer], None]], Callable[[Renderer], None]]:
    def register(fn: Callable[[Renderer], None]) -> Callable[[Renderer], None]:
        CONTRACTS.append((name, fn))
        return fn

    return register


@contract("helm-lint")
def helm_lint(r: Renderer) -> None:
    r.lint()


@contract("base-graceful-termination")
def base_graceful_termination(r: Renderer) -> None:
    base = r.get("base")
    base.exact_lines("      terminationGracePeriodSeconds: 30", 2, "base-graceful-termination")
    base.exact_lines("          lifecycle:", 0, "base-graceful-termination")


@contract("base-excludes-canary-objects")
def base_excludes_canary_objects(r: Renderer) -> None:
    base = r.get("base")
    base.excludes_pattern(r"  name: api-canary", "base-excludes-canary-objects")
    base.excludes_pattern(r"  name: web-canary", "base-excludes-canary-objects")


@contract("migration-disabled-renders-no-job")
def migration_disabled_renders_no_job(r: Renderer) -> None:
    r.get("base-migration-off").excludes_pattern(
        r"kind: Job", "migration-disabled-renders-no-job"
    )


@contract("digest-pinning-replaces-mutable-tags")
def digest_pinning_replaces_mutable_tags(r: Renderer) -> None:
    rendered = r.get("base-digest")
    name = "digest-pinning-replaces-mutable-tags"
    rendered.contains(f"localhost/bedoux-api@{_DIGEST}", name)
    rendered.contains(f"localhost/bedoux-web@{_DIGEST}", name)
    rendered.excludes("localhost/bedoux-api:p3", name)
    rendered.excludes("localhost/bedoux-web:p3", name)


@contract("aws-stable-forward-is-100-percent")
def aws_stable_forward_is_100_percent(r: Renderer) -> None:
    rendered = r.get("aws")
    name = "aws-stable-forward-is-100-percent"
    rendered.contains(
        r'\"serviceName\":\"web\",\"servicePort\":8080,\"weight\":100', name
    )
    rendered.contains("name: use-annotation", name)
    rendered.excludes(r'serviceName\":\"web-canary', name)


@contract("aws-deregistration-delay-is-pinned")
def aws_deregistration_delay_is_pinned(r: Renderer) -> None:
    r.get("aws-dereg30").contains(
        'alb.ingress.kubernetes.io/target-group-attributes: '
        '"deregistration_delay.timeout_seconds=30"',
        "aws-deregistration-delay-is-pinned",
    )


@contract("aws-tls-uses-acm-discovery")
def aws_tls_uses_acm_discovery(r: Renderer) -> None:
    rendered = r.get("aws-tls")
    name = "aws-tls-uses-acm-discovery"
    rendered.contains(
        "alb.ingress.kubernetes.io/listen-ports: '[{\"HTTP\":80},{\"HTTPS\":443}]'", name
    )
    rendered.contains('alb.ingress.kubernetes.io/ssl-redirect: "443"', name)
    rendered.matching_lines(r'    - host: ".*bedoux\.ca"', 2, name)
    rendered.matching_lines(r'        - ".*bedoux\.ca"', 2, name)
    # An ARN would carry the AWS account ID into source control.
    rendered.excludes("alb.ingress.kubernetes.io/certificate-arn", name)


@contract("kind-ha-has-pdbs-and-spread")
def kind_ha_has_pdbs_and_spread(r: Renderer) -> None:
    rendered = r.get("kind-ha")
    name = "kind-ha-has-pdbs-and-spread"
    rendered.exact_lines("kind: PodDisruptionBudget", 2, name)
    rendered.exact_lines("      topologySpreadConstraints:", 2, name)


@contract("aws-ha-has-pdbs-spread-and-drain-window")
def aws_ha_has_pdbs_spread_and_drain_window(r: Renderer) -> None:
    rendered = r.get("aws-ha")
    name = "aws-ha-has-pdbs-spread-and-drain-window"
    rendered.exact_lines("kind: PodDisruptionBudget", 2, name)
    rendered.exact_lines("      topologySpreadConstraints:", 2, name)
    rendered.exact_lines("          whenUnsatisfiable: ScheduleAnyway", 2, name)
    rendered.exact_lines("      terminationGracePeriodSeconds: 60", 2, name)
    rendered.exact_lines("          lifecycle:", 2, name)
    rendered.exact_lines('                  - "sleep 45"', 2, name)
    rendered.contains(
        'alb.ingress.kubernetes.io/target-group-attributes: '
        '"deregistration_delay.timeout_seconds=30"',
        name,
    )


@contract("aws-rds-profile-renders")
def aws_rds_profile_renders(r: Renderer) -> None:
    r.get("aws-rds")


@contract("canary-objects-and-weights")
def canary_objects_and_weights(r: Renderer) -> None:
    rendered = r.get("aws-canary")
    name = "canary-objects-and-weights"
    rendered.exact_lines("  name: api-canary", 2, name)
    rendered.exact_lines("  name: web-canary", 2, name)
    rendered.contains("API_UPSTREAM: api-canary:8000", name)
    rendered.contains(r'\"serviceName\":\"web\",\"servicePort\":8080,\"weight\":90', name)
    rendered.contains(
        r'\"serviceName\":\"web-canary\",\"servicePort\":8080,\"weight\":10', name
    )
    rendered.contains(f"localhost/bedoux-api@{_CANDIDATE_DIGEST}", name)
    rendered.contains(f"localhost/bedoux-web@{_CANDIDATE_DIGEST}", name)


@contract("canary-regression-mode-retargets-upstream")
def canary_regression_mode_retargets_upstream(r: Renderer) -> None:
    r.get("aws-canary-regression").contains(
        "API_UPSTREAM: api-canary:8000/__p13-regression",
        "canary-regression-mode-retargets-upstream",
    )


@contract("cleanup-render-is-stable-only")
def cleanup_render_is_stable_only(r: Renderer) -> None:
    rendered = r.get("aws-cleanup")
    name = "cleanup-render-is-stable-only"
    rendered.contains(r'\"serviceName\":\"web\",\"servicePort\":8080,\"weight\":100', name)
    rendered.excludes_pattern(r"kind: Job", name)
    rendered.excludes("web-canary", name)
    rendered.excludes("api-canary", name)


@contract("invalid-profiles-fail-closed")
def invalid_profiles_fail_closed(r: Renderer) -> None:
    name = "invalid-profiles-fail-closed"
    for profile in FAIL_CLOSED_PROFILES:
        r.expect_render_failure(profile, name)


@contract("ha-canary-inherits-topology-spread")
def ha_canary_inherits_topology_spread(r: Renderer) -> None:
    """ADR 0024: the canary renders the same soft spread as its stable counterpart.

    Replaces M1's ha-canary-topology-divergence-pending-m2, which pinned the divergence in
    place until M2 decided. A no-op at canary.replicas=1 by design — the contract exists so
    the gap cannot reopen silently if replicas are ever raised.
    """
    spread = r.get("aws-ha-canary").deployments_with_topology_spread()
    name = "ha-canary-inherits-topology-spread"
    expected = {"api", "web", "api-canary", "web-canary"}
    if spread != expected:
        raise ContractError(
            "aws-ha-canary",
            name,
            f"expected topology spread on {sorted(expected)} per ADR 0024, "
            f"found {sorted(spread)}",
        )


@contract("stable-and-canary-pod-specs-stay-equivalent")
def stable_and_canary_pod_specs_stay_equivalent(r: Renderer) -> None:
    """ADR 0024: the two pod specs differ only where a parameter makes them differ.

    Both sides render from one shared module, so this compares the rendered pod specs after
    normalising the intended differences away. Anything left is drift.
    """
    rendered = r.get("aws-canary")
    name = "stable-and-canary-pod-specs-stay-equivalent"
    for stable, canary in (("api", "api-canary"), ("web", "web-canary")):
        stable_spec = rendered.pod_spec(stable)
        canary_spec = rendered.pod_spec(canary)
        if stable_spec is None or canary_spec is None:
            raise ContractError(
                "aws-canary", name, f"could not locate pod specs for {stable}/{canary}"
            )
        # Normalise the parameterised differences: pod label/selector, image, ConfigMap.
        normalised = (
            canary_spec.replace(f"app: {canary}", f"app: {stable}")
            .replace(f"name: {canary}-config", f"name: {stable}-config")
            .replace(_CANDIDATE_DIGEST, _DIGEST)
        )
        if normalised != stable_spec:
            diff = "\n".join(
                line
                for line in difflib.unified_diff(
                    stable_spec.splitlines(), normalised.splitlines(), lineterm="", n=0
                )
                if line.startswith(("+", "-")) and not line.startswith(("+++", "---"))
            )
            raise ContractError(
                "aws-canary",
                name,
                f"{stable} and {canary} pod specs diverged beyond their parameters:\n{diff}",
            )


# --------------------------------------------------------------------------------------
# Fail sensitivity — prove the contracts above reject a deliberately broken chart.
# --------------------------------------------------------------------------------------

@contextmanager
def mutated_chart(old: str, new: str, template: str) -> Iterator[Renderer]:
    """Copy the chart, rewrite one template, and yield a Renderer over the copy."""
    with tempfile.TemporaryDirectory(prefix="bedoux-m1-render-fixture-") as tmp:
        chart_copy = Path(tmp) / "bedoux"
        shutil.copytree(CHART_DIR, chart_copy)
        target = chart_copy / "templates" / template
        source = target.read_text()
        if old not in source:
            raise HarnessError(
                f"fixture anchor not found in {template}: {old!r} — the fixture is stale"
            )
        target.write_text(source.replace(old, new))
        yield Renderer(chart_copy)


FIXTURES: list[tuple[str, str, str, str, str]] = [
    # (description, template, old, new, contract that must reject it)
    (
        "stable API loses its topology spread",
        "_helpers.tpl",
        "{{- if $api.topologySpread.enabled }}",
        "{{- if false }}",
        "aws-ha-has-pdbs-spread-and-drain-window",
    ),
    (
        "termination grace period drifts off 30s",
        "_helpers.tpl",
        "terminationGracePeriodSeconds: {{ $api.termination.gracePeriodSeconds }}",
        "terminationGracePeriodSeconds: 31",
        "base-graceful-termination",
    ),
    (
        "ALB stops forwarding through the annotation action",
        "ingress.yaml",
        "name: use-annotation",
        "name: web",
        "aws-stable-forward-is-100-percent",
    ),
    (
        "canary Deployment/Service loses its name",
        "canary.yaml",
        "name: api-canary",
        "name: api-shadow",
        "canary-objects-and-weights",
    ),
    # The next two reintroduce, one side at a time, exactly the class of drift ADR 0024
    # closed. Both must be asymmetric: mutating the shared module symmetrically changes
    # stable and canary together, which these contracts would correctly not flag.
    (
        "canary loses the spread ADR 0024 gave it",
        "_helpers.tpl",
        "{{- if $api.topologySpread.enabled }}",
        '{{- if and $api.topologySpread.enabled (eq .app "api") }}',
        "ha-canary-inherits-topology-spread",
    ),
    (
        "canary pod spec drifts from the stable one",
        "_helpers.tpl",
        "      initialDelaySeconds: 3\n      periodSeconds: 5",
        '      initialDelaySeconds: {{ if eq .app "api" }}3{{ else }}4{{ end }}\n'
        "      periodSeconds: 5",
        "stable-and-canary-pod-specs-stay-equivalent",
    ),
]

CONTRACTS_BY_NAME = dict(CONTRACTS)


def check_fail_sensitivity() -> list[str]:
    """Each fixture must make its contract raise. A contract that still passes is vacuous."""
    failures: list[str] = []
    for description, template, old, new, contract_name in FIXTURES:
        check = CONTRACTS_BY_NAME.get(contract_name)
        if check is None:
            raise HarnessError(f"fixture references unknown contract '{contract_name}'")
        with mutated_chart(old, new, template) as broken:
            try:
                check(broken)
            except ContractError:
                print(f"  rejected  {description}  ->  {contract_name}")
                continue
            failures.append(
                f"  ACCEPTED  {description}  ->  {contract_name} did not reject the fixture"
            )
    return failures


def main() -> int:
    if not CHART_DIR.is_dir():
        print(f"chart directory not found: {CHART_DIR}", file=sys.stderr)
        return 2

    renderer = Renderer(CHART_DIR)
    failures: list[str] = []

    print("Render contracts:")
    for name, check in CONTRACTS:
        try:
            check(renderer)
        except ContractError as exc:
            print(f"  FAIL      {name}")
            failures.append(f"  {exc}")
        else:
            print(f"  ok        {name}")

    print("\nFail sensitivity:")
    try:
        failures.extend(check_fail_sensitivity())
    except HarnessError as exc:
        print(f"\nHARNESS ERROR: {exc}", file=sys.stderr)
        return 2

    if failures:
        print("\nFAILED:", file=sys.stderr)
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1

    print(
        f"\nOK — {len(CONTRACTS)} render contracts and {len(FIXTURES)} negative fixtures passed "
        f"across {len(renderer._cache)} cached renders."
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except HarnessError as exc:
        print(f"HARNESS ERROR: {exc}", file=sys.stderr)
        sys.exit(2)
