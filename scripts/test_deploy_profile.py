#!/usr/bin/env python3
"""M3: exhaustive proof that scripts/lib/deploy_profile.py matches the workflow it replaced.

The workflow's 8 booleans give 2**8 = 256 combinations -- small enough to check every one,
so this does. ``reference()`` below is a deliberately separate, deliberately dumb
transcription of the *original* inline bash from deploy-learning.yml's "Deploy the Helm
release" step, kept in this file rather than imported from deploy_profile.py so a bug shared
between the two could not hide. For every one of the 256 combinations, this asserts:

* both refuse, with the same message, or
* both accept, with the same mode, timeout, values files (order matters), extra args (order
  matters), and preflight checks (order matters).

This is the same technique M2 used (golden-render comparison against the pre-refactor chart)
applied to a decision table instead of a Helm template: enumerate every input the old and new
implementations disagree over, and prove there are none.
"""

from __future__ import annotations

import itertools
import sys
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import deploy_profile as m  # noqa: E402

FLAGS = [
    "seed_catalog",
    "rollback_drill",
    "use_rds",
    "use_secrets_manager",
    "use_s3_images",
    "use_custom_domain",
    "canary_rollout",
    "canary_regression_drill",
]


@dataclass(frozen=True)
class ReferenceResult:
    ok: bool
    message: str = ""
    mode: str = ""
    timeout: str = ""
    values_files: list[str] = field(default_factory=list)
    extra_args: list[str] = field(default_factory=list)
    preflight: list[str] = field(default_factory=list)


def reference(
    seed_catalog: bool,
    rollback_drill: bool,
    use_rds: bool,
    use_secrets_manager: bool,
    use_s3_images: bool,
    use_custom_domain: bool,
    canary_rollout: bool,
    canary_regression_drill: bool,
) -> ReferenceResult:
    """Transcribed line-for-line from deploy-learning.yml's pre-M3 "Deploy the Helm release"
    step (see git history: .github/workflows/deploy-learning.yml before this commit)."""

    release_timeout = "10m"
    if rollback_drill:
        release_timeout = "3m"
    if use_custom_domain and rollback_drill:
        return ReferenceResult(
            False, "P12 custom-domain proof and the rollback drill must run in separate sessions."
        )
    if canary_rollout and rollback_drill:
        return ReferenceResult(False, "canary_rollout and rollback_drill are separate evidence paths.")
    if canary_rollout and canary_regression_drill:
        return ReferenceResult(False, "canary_rollout and canary_regression_drill are mutually exclusive.")
    if canary_regression_drill and rollback_drill:
        return ReferenceResult(
            False, "canary_regression_drill and rollback_drill are separate evidence paths."
        )
    if (canary_rollout or canary_regression_drill) and seed_catalog:
        return ReferenceResult(
            False, "canary paths require an existing seeded baseline; set seed_catalog=false."
        )
    if canary_regression_drill and (
        use_rds or use_secrets_manager or use_s3_images or use_custom_domain
    ):
        return ReferenceResult(
            False, "canary_regression_drill requires every unrelated deployment option false."
        )

    profile_files = ["charts/bedoux/values.yaml", "charts/bedoux/values-aws.yaml"]
    helm_extra_args: list[str] = []
    if rollback_drill:
        helm_extra_args += [
            "--set-json",
            'web.command=["sh","-c","echo signed rollback drill failure >&2; exit 1"]',
        ]
    if use_secrets_manager and not use_rds:
        return ReferenceResult(False, "use_secrets_manager requires use_rds=true")
    if use_secrets_manager and use_s3_images:
        return ReferenceResult(
            False,
            "P7.2 S3 and P7.3 Secrets Manager identities are separate; "
            "run those proofs independently.",
        )
    if use_rds:
        profile_files.append("charts/bedoux/values-aws-rds.yaml")

    preflight: list[str] = []
    if use_secrets_manager:
        preflight.append("exists serviceaccount bedoux-api-secrets")
        preflight.append("absent secret rds-credentials")
        profile_files.append("charts/bedoux/values-aws-secrets.yaml")
    elif use_rds:
        preflight.append("exists secret rds-credentials")
    if use_s3_images:
        preflight.append("exists serviceaccount bedoux-api")
        preflight.append("exists configmap bedoux-image-storage")
        profile_files.append("charts/bedoux/values-aws-s3.yaml")
    if use_custom_domain:
        profile_files.append("charts/bedoux/values-aws-tls.yaml")
    if seed_catalog:
        helm_extra_args += ["--set", "seed.enabled=true"]

    mode = "canary" if (canary_rollout or canary_regression_drill) else "helm"

    return ReferenceResult(
        True,
        mode=mode,
        timeout=release_timeout,
        values_files=profile_files,
        extra_args=helm_extra_args,
        preflight=preflight,
    )


def main() -> int:
    checked = 0
    accepted = 0
    refused = 0
    failures: list[str] = []

    for bits in itertools.product([False, True], repeat=len(FLAGS)):
        kwargs = dict(zip(FLAGS, bits))
        checked += 1
        label = " ".join(f"{k}={str(v).lower()}" for k, v in kwargs.items())
        ref = reference(**kwargs)

        try:
            profile = m.resolve(**kwargs)
        except m.InvalidProfile as exc:
            if ref.ok:
                failures.append(f"{label}: resolve() refused ({exc}) but reference() accepted")
            elif str(exc) != ref.message:
                failures.append(
                    f"{label}: refusal message differs\n"
                    f"    resolve():    {exc}\n"
                    f"    reference():  {ref.message}"
                )
            else:
                refused += 1
            continue

        if not ref.ok:
            failures.append(f"{label}: resolve() accepted but reference() refused ({ref.message})")
            continue

        accepted += 1
        if profile.mode != ref.mode:
            failures.append(f"{label}: mode differs: {profile.mode!r} vs {ref.mode!r}")
        if profile.release_timeout != ref.timeout:
            failures.append(
                f"{label}: release_timeout differs: {profile.release_timeout!r} vs {ref.timeout!r}"
            )
        if profile.values_files != ref.values_files:
            failures.append(
                f"{label}: values_files differ:\n"
                f"    resolve():    {profile.values_files}\n"
                f"    reference():  {ref.values_files}"
            )
        if profile.helm_extra_args != ref.extra_args:
            failures.append(
                f"{label}: helm_extra_args differ:\n"
                f"    resolve():    {profile.helm_extra_args}\n"
                f"    reference():  {ref.extra_args}"
            )
        preflight_strs = [str(check) for check in profile.preflight_checks]
        if preflight_strs != ref.preflight:
            failures.append(
                f"{label}: preflight_checks differ:\n"
                f"    resolve():    {preflight_strs}\n"
                f"    reference():  {ref.preflight}"
            )

    if failures:
        print(f"FAILED: {len(failures)} of {checked} combinations disagree:", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1

    print(
        f"OK — {checked} combinations checked exhaustively (2**{len(FLAGS)}): "
        f"{accepted} accepted and matched exactly, {refused} refused with an identical message."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
