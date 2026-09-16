#!/usr/bin/env python3
"""GO-1 Gate 6a durable first-attempt claim (design-contract tooling, not yet wired
into any live bootstrap flow — GO-3 does that). No cluster, network or AWS access;
state is a local claim file.

Corrected per Codex's third GO-1 review (docs/PROGRESS.md session log
2026-09-09T14:37:25-06:00): `gitops_bootstrap_precondition_check.py` is a READ-ONLY
predicate over `status/<environment>.yaml`. Reading it twice, with nothing recorded
in between, legitimately returns the same answer twice — that is correct behavior
for a read-only predicate, but it is not, by itself, proof that nothing has run. A
crash between "the precondition check said proceed" and "the deploy actually
started" leaves the exact same evidence as never having started at all, so a naive
retry (or a second concurrent invocation) cannot tell "safe to attempt" from
"already attempting, in flight." This script adds the missing, SEPARATE, durable
primitive: a serialized claim that must be acquired before deployment starts, and
explicitly consumed only after the outcome is durably recorded in the status file.
The precondition checker's read-only decision logic is unchanged by this file.

Real-cluster mapping (GO-3 wiring, not built here): the claim's required property —
atomic create-if-absent, keyed by (environment, releaseId) — is exactly what a
Kubernetes object's name uniqueness already gives for free (`kubectl create
configmap claim-<environment>-<releaseId>` fails if one exists). This script models
that same atomicity locally with `open(path, "x")` (POSIX O_EXCL semantics): a
second concurrent claim or a post-crash retry against the SAME (environment,
releaseId) will observe the first claim's file and refuse, exactly as a second
`kubectl create` against the same object name would fail with AlreadyExists.

Required sequence (documented in docs/runbooks/gitops-recovery.md's bootstrap
section): `claim` (this file) -> `gitops_bootstrap_precondition_check.py` -> deploy
-> outcome recorded in `status/<environment>.yaml` -> `consume` (this file). Only
`consume` removes a claim; there is no "release without consuming" operation. This
is deliberate: a crash between `claim` and `consume` must ALWAYS leave durable
evidence behind (the claim file itself persists), so a retry after a crash is
refused by construction, not merely by convention. Resolving a leftover claim after
a genuine crash requires an operator to inspect what actually happened, record an
explicit outcome (healthy/rejected/unknown) in the status file, and only then
manually remove the stale claim file — this script deliberately provides no
automatic staleness/TTL expiry, since guessing "enough time has passed, it must be
safe to retry" is exactly the fail-open behavior Gate 6a already rejects elsewhere.

Exit codes:
  0  claim: a fresh claim was acquired for (environment, releaseId).
     consume: an existing claim for (environment, releaseId) was removed.
  1  claim: refused — a claim already exists for (environment, releaseId): either a
     genuinely concurrent attempt, or a crashed prior attempt that was never
     consumed. Either way, this exact releaseId must not be retried automatically;
     resolve via the recovery runbook (record an explicit outcome, then an operator
     removes the stale claim) before trying again.
     consume: refused — no claim exists for (environment, releaseId); consuming
     without first claiming is an ordering violation and is never allowed to
     silently succeed.
  2x (usage) — argument/file errors, via argparse/explicit checks below.
"""
import argparse
import datetime
import sys
from pathlib import Path


def claim_path(claims_dir: Path, environment: str, release_id: str) -> Path:
    # environment/releaseId are expected to be short, reviewed, human-chosen
    # identifiers (see the release record schema) — not sanitized further here,
    # matching how the release record and status record already trust these same
    # fields as plain YAML scalars.
    return claims_dir / f"{environment}__{release_id}.claim"


def cmd_claim(args) -> int:
    claims_dir = Path(args.claims_dir)
    claims_dir.mkdir(parents=True, exist_ok=True)
    path = claim_path(claims_dir, args.environment, args.release_id)
    now = datetime.datetime.now(datetime.timezone.utc).isoformat()
    body = (
        f"environment: {args.environment}\n"
        f"releaseId: \"{args.release_id}\"\n"
        f"claimedAt: \"{now}\"\n"
        f"claimant: \"{args.claimant}\"\n"
    )
    try:
        # 'x' mode = O_CREAT|O_EXCL: atomically fails if the file already exists.
        # This exclusivity, not any locking discipline in the caller, is what makes
        # concurrent/replayed claims for the same (environment, releaseId) refuse.
        with open(path, "x") as fh:
            fh.write(body)
    except FileExistsError:
        try:
            existing = path.read_text()
        except OSError:
            existing = "<could not read existing claim file>"
        print(
            f"REFUSE: a claim already exists for environment '{args.environment}' "
            f"releaseId '{args.release_id}' at {path} — either a genuinely "
            "concurrent attempt, or a prior attempt crashed before it was "
            "consumed. Do not retry automatically: resolve via the recovery "
            "runbook's bootstrap-after-failure procedure (record an explicit "
            "outcome for this releaseId, then an operator removes this stale "
            f"claim file) before trying again. Existing claim:\n{existing}",
            file=sys.stderr,
        )
        return 1
    print(
        f"CLAIMED: environment '{args.environment}' releaseId '{args.release_id}' "
        f"at {path}. This claim must be consumed (this script's 'consume' "
        "subcommand) only after the deployment outcome is durably recorded in "
        "status/<environment>.yaml — never before, and never on a bare success "
        "return from the deploy step alone."
    )
    return 0


def cmd_consume(args) -> int:
    claims_dir = Path(args.claims_dir)
    path = claim_path(claims_dir, args.environment, args.release_id)
    try:
        path.unlink()
    except FileNotFoundError:
        print(
            f"REFUSE: no claim exists for environment '{args.environment}' "
            f"releaseId '{args.release_id}' at {path} — consuming a claim that "
            "was never acquired is an ordering violation (claim must precede "
            "deploy must precede consume) and is never allowed to silently "
            "succeed.",
            file=sys.stderr,
        )
        return 1
    print(f"CONSUMED: environment '{args.environment}' releaseId '{args.release_id}' claim at {path} removed.")
    return 0


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--claims-dir", required=True, help="Directory holding claim files (local stand-in for a real cluster object store).")
    common.add_argument("--environment", required=True)
    common.add_argument("--release-id", required=True)

    p_claim = sub.add_parser("claim", parents=[common], help="Atomically acquire a durable first-attempt claim before deploying.")
    p_claim.add_argument("--claimant", default="unspecified", help="Free-text identity of the caller, recorded for diagnosis only (not trusted for authorization).")
    p_claim.set_defaults(func=cmd_claim)

    p_consume = sub.add_parser("consume", parents=[common], help="Remove a claim after its outcome is durably recorded in status/<environment>.yaml.")
    p_consume.set_defaults(func=cmd_consume)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
