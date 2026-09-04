#!/usr/bin/env python3
"""M3: resolve deploy-learning.yml's 8 boolean inputs into one named deployment profile.

Before M3, the workflow's "Deploy the Helm release" step interleaved validation, Helm
values-file selection, and live kubectl preflight checks inline, all keyed off 8 independent
booleans (2**8 = 256 combinations). Whether a given combination was legal, which values files
it produced, and in what order, was only discoverable by dispatching a real, paid AWS session.
A stride-2 loop then re-parsed the flat ``profile_files`` array backwards to hand the canary
path its values files, because there was no first-class representation of a resolved profile.

This module is that representation. ``resolve()`` is pure -- no AWS or Kubernetes access, no
I/O -- and takes exactly the 8 booleans the workflow already exposes as inputs. It either
raises :class:`InvalidProfile` (mirroring one of the workflow's original refusal messages
verbatim) or returns a :class:`DeployProfile` naming:

* ``mode`` -- ``"helm"`` or ``"canary"``, which deployment path to take;
* ``release_timeout`` -- ``"10m"`` normally, ``"3m"`` during a rollback drill;
* ``values_files`` -- the ordered Helm ``-f`` paths, as bare paths (no ``-f`` prefix, so both
  a direct ``helm upgrade`` and ``p13-canary-rollout.sh --values`` can consume the same list
  without any backward re-parsing);
* ``helm_extra_args`` -- additional non-secret ``--set``/``--set-json`` tokens;
* ``preflight_checks`` -- declarative facts about cluster state a caller must verify before
  proceeding (this module has no cluster access, so it can only say what must be true, not
  check it).

Every rule, message, and ordering decision here is a verbatim transcription of the workflow's
prior inline bash, verified by ``scripts/test_deploy_profile.py`` exhaustively over all 256
combinations against an independent reference implementation. See ADR-less M3 session log entry
in docs/PROGRESS.md: this is a pure refactor, not a behaviour change.
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass, field


class InvalidProfile(Exception):
    """The 8 inputs describe an illegal combination. Message matches the prior refusal text."""


@dataclass(frozen=True)
class PreflightCheck:
    """A fact about live cluster state the caller must verify before deploying.

    kind is "exists" (the resource must be present) or "absent" (the resource must NOT be
    present). This module cannot check either itself -- it has no cluster access -- so it
    hands the caller a declarative list instead of doing the check inline, the way the
    original bash did.
    """

    kind: str
    resource: str
    name: str

    def __str__(self) -> str:
        return f"{self.kind} {self.resource} {self.name}"


@dataclass(frozen=True)
class DeployProfile:
    mode: str
    release_timeout: str
    values_files: list[str] = field(default_factory=list)
    helm_extra_args: list[str] = field(default_factory=list)
    preflight_checks: list[PreflightCheck] = field(default_factory=list)


def resolve(
    *,
    seed_catalog: bool,
    rollback_drill: bool,
    use_rds: bool,
    use_secrets_manager: bool,
    use_s3_images: bool,
    use_custom_domain: bool,
    canary_rollout: bool,
    canary_regression_drill: bool,
) -> DeployProfile:
    """Validate and resolve the 8 workflow_dispatch booleans. Raises InvalidProfile or returns
    a DeployProfile. Checked in the same order the prior inline bash checked them, so the
    refusal message for any illegal combination is unchanged."""

    if use_custom_domain and rollback_drill:
        raise InvalidProfile(
            "P12 custom-domain proof and the rollback drill must run in separate sessions."
        )
    if canary_rollout and rollback_drill:
        raise InvalidProfile("canary_rollout and rollback_drill are separate evidence paths.")
    if canary_rollout and canary_regression_drill:
        raise InvalidProfile("canary_rollout and canary_regression_drill are mutually exclusive.")
    if canary_regression_drill and rollback_drill:
        raise InvalidProfile(
            "canary_regression_drill and rollback_drill are separate evidence paths."
        )
    if (canary_rollout or canary_regression_drill) and seed_catalog:
        raise InvalidProfile(
            "canary paths require an existing seeded baseline; set seed_catalog=false."
        )
    if canary_regression_drill and (
        use_rds or use_secrets_manager or use_s3_images or use_custom_domain
    ):
        raise InvalidProfile(
            "canary_regression_drill requires every unrelated deployment option false."
        )
    if use_secrets_manager and not use_rds:
        raise InvalidProfile("use_secrets_manager requires use_rds=true")
    if use_secrets_manager and use_s3_images:
        raise InvalidProfile(
            "P7.2 S3 and P7.3 Secrets Manager identities are separate; "
            "run those proofs independently."
        )

    values_files = ["charts/bedoux/values.yaml", "charts/bedoux/values-aws.yaml"]
    if use_rds:
        values_files.append("charts/bedoux/values-aws-rds.yaml")
    if use_secrets_manager:
        values_files.append("charts/bedoux/values-aws-secrets.yaml")
    if use_s3_images:
        values_files.append("charts/bedoux/values-aws-s3.yaml")
    if use_custom_domain:
        values_files.append("charts/bedoux/values-aws-tls.yaml")

    helm_extra_args: list[str] = []
    if rollback_drill:
        helm_extra_args += [
            "--set-json",
            'web.command=["sh","-c","echo signed rollback drill failure >&2; exit 1"]',
        ]
    if seed_catalog:
        helm_extra_args += ["--set", "seed.enabled=true"]

    preflight_checks: list[PreflightCheck] = []
    if use_secrets_manager:
        preflight_checks.append(PreflightCheck("exists", "serviceaccount", "bedoux-api-secrets"))
        preflight_checks.append(PreflightCheck("absent", "secret", "rds-credentials"))
    elif use_rds:
        preflight_checks.append(PreflightCheck("exists", "secret", "rds-credentials"))
    if use_s3_images:
        preflight_checks.append(PreflightCheck("exists", "serviceaccount", "bedoux-api"))
        preflight_checks.append(PreflightCheck("exists", "configmap", "bedoux-image-storage"))

    return DeployProfile(
        mode="canary" if (canary_rollout or canary_regression_drill) else "helm",
        release_timeout="3m" if rollback_drill else "10m",
        values_files=values_files,
        helm_extra_args=helm_extra_args,
        preflight_checks=preflight_checks,
    )


# --------------------------------------------------------------------------------------
# CLI -- one subcommand per field, all sharing the same validation via resolve(). An
# invalid combination refuses identically (same message, same exit status) from every
# subcommand, so bash can never see one field say "valid" while another says "invalid".
# --------------------------------------------------------------------------------------


def _bool(value: str) -> bool:
    if value not in ("true", "false"):
        raise argparse.ArgumentTypeError(f"expected 'true' or 'false', got {value!r}")
    return value == "true"


def _add_input_flags(parser: argparse.ArgumentParser) -> None:
    for flag in (
        "seed-catalog",
        "rollback-drill",
        "use-rds",
        "use-secrets-manager",
        "use-s3-images",
        "use-custom-domain",
        "canary-rollout",
        "canary-regression-drill",
    ):
        parser.add_argument(f"--{flag}", required=True, type=_bool)


def _resolve_from_args(args: argparse.Namespace) -> DeployProfile:
    return resolve(
        seed_catalog=args.seed_catalog,
        rollback_drill=args.rollback_drill,
        use_rds=args.use_rds,
        use_secrets_manager=args.use_secrets_manager,
        use_s3_images=args.use_s3_images,
        use_custom_domain=args.use_custom_domain,
        canary_rollout=args.canary_rollout,
        canary_regression_drill=args.canary_regression_drill,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="deploy_profile", description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    for name in ("mode", "release-timeout", "values-files", "helm-extra-args", "preflight-checks"):
        _add_input_flags(subparsers.add_parser(name))

    args = parser.parse_args(argv)

    try:
        profile = _resolve_from_args(args)
    except InvalidProfile as exc:
        print(f"REFUSING: {exc}", file=sys.stderr)
        return 1

    if args.command == "mode":
        print(profile.mode)
    elif args.command == "release-timeout":
        print(profile.release_timeout)
    elif args.command == "values-files":
        for path in profile.values_files:
            print(path)
    elif args.command == "helm-extra-args":
        for token in profile.helm_extra_args:
            print(token)
    elif args.command == "preflight-checks":
        for check in profile.preflight_checks:
            print(check)
    return 0


if __name__ == "__main__":
    sys.exit(main())
