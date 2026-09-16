#!/usr/bin/env python3
"""GO-1 Gate 6a bootstrap-precondition check (design-contract tooling, not yet wired
into any live bootstrap flow — GO-3 does that). Reads a release record and its
environment's release-outcome record and decides whether it is safe to enable Argo
auto-sync for the release record's CURRENT releaseId. No cluster, network or AWS
access; both inputs are local files.

Corrected per Codex's first GO-1 review (docs/PROGRESS.md session log
2026-09-09T11:03:16-06:00): the earlier design let a still-selected REJECTED release
through if some LATER releaseId happened to be marked healthy elsewhere in history
(the `supersededBy` field was wrongly treated as a live bypass). `supersededBy` is
audit metadata only. Fail-closed: proceed only on an explicit `healthy` entry for
the exact current releaseId, OR on a `pending` entry that is the SOLE (first-ever)
entry recorded for that releaseId — see below.

Corrected per Codex's second GO-1 review (docs/PROGRESS.md session log
2026-09-09T13:29:08-06:00): naively refusing every `pending` outcome created a
self-contradiction — the design's own recovery contract has every promotion write a
`pending` entry for its own releaseId in the SAME PR, meaning a brand-new
environment's very first release would ALWAYS be `pending` (never `healthy`, since
nothing has run yet to confirm it) and could therefore never bootstrap at all, even
though a reviewed promotion PR IS the explicit approval to attempt it — there is
nothing further to "confirm" before a first attempt.

The fix distinguishes an APPROVED FIRST ATTEMPT from a REPLAY of something already
attempted:
  - `pending` PROCEEDS only when it is the ONLY entry ever recorded for that exact
    releaseId (len(matching) == 1) — a reviewed promotion PR approved this
    releaseId to be tried, and nothing else has ever been recorded about it. This
    is a durable, explicit approval, not "missing evidence."
  - `pending` REFUSES (distinctly from `rejected`) if MORE than one entry exists
    for that releaseId — e.g. an attempt was already made and something is now
    trying to re-approve the SAME releaseId by appending another pending row
    instead of promoting a genuinely new one. Real recovery always mints a new
    releaseId (see docs/runbooks/gitops-recovery.md); reusing an old one after any
    prior entry is itself a process violation and is refused, not silently allowed.
  - `unknown` (an attempt was made but its outcome was never durably confirmed —
    e.g. the cluster was lost mid-check) ALWAYS refuses, regardless of entry count.
    It is never eligible for the first-attempt bypass, because by definition
    something already happened and its result is uncertain — the opposite of a
    genuinely fresh, never-tried release.
  - A never-deployed release is never marked `healthy`. `healthy` is only ever
    written after a real confirmation (GO-4 promotion evidence or a GO-3/GO-5 live
    check) — this script does not, and must not, invent that confirmation itself.

Exit codes (all "cannot proceed" codes are deliberately distinct so a caller/test can
tell them apart, not just "success vs failure"):
  0  proceed — explicit `healthy`, or `pending` as the sole/first-ever entry for
     this exact releaseId (approved first attempt), or a verified first-ever
     bootstrap (--allow-first-bootstrap, environment history empty/absent).
  1  refuse — the current releaseId is explicitly `rejected`.
  2  refuse — the current releaseId is `pending` but NOT the sole entry (a replay
     of something already attempted, not a fresh approval).
  3  refuse — no entry exists for the current releaseId at all (and this is not a
     verified first-ever bootstrap). Missing evidence never proceeds.
  4  refuse — malformed input (unknown outcome value, missing required fields, or
     the release record's environment does not match the status record's).
  5  refuse — the current releaseId is explicitly `unknown` (attempted, outcome
     never confirmed) — never eligible for any bypass.
  6  refuse — a durable attempt claim already exists for this exact releaseId
     (only checked when --claims-dir is given; see below). This is a defense-in-
     depth check, not the primary mechanism: the primary fix for "this predicate
     cannot prove nothing has run" is the SEPARATE, mandatory
     `gitops_release_attempt_claim.py claim` step a real caller must perform
     before deploying (documented in docs/runbooks/gitops-recovery.md's bootstrap
     section) — this flag only catches a caller that reaches this checker with a
     stale claim already outstanding (e.g. re-running the checker itself during a
     crashed prior attempt), it does not replace the caller's own obligation to
     claim.
  2x (usage) — argument/file errors, via argparse/explicit checks below.

Corrected per Codex's third GO-1 review (docs/PROGRESS.md session log
2026-09-09T14:37:25-06:00): this checker is a READ-ONLY predicate over
`status/<environment>.yaml`. Running it twice with nothing recorded in between
legitimately returns the same answer both times — that is correct for a read-only
predicate, but it is not, by itself, proof that no deployment attempt is already in
flight or crashed mid-attempt. `--claims-dir` (optional here) lets this checker also
refuse when a `gitops_release_attempt_claim.py` claim is already outstanding for
this exact releaseId; the actual serialization guarantee comes from that separate
script's atomic claim-file creation, not from this predicate being re-evaluated.
"""
import argparse
import sys
from pathlib import Path

import yaml

KNOWN_OUTCOMES = {"healthy", "rejected", "pending", "unknown"}


def load_yaml(path):
    with open(path) as fh:
        return yaml.safe_load(fh)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release-record", required=True)
    parser.add_argument("--status-record", required=True)
    parser.add_argument(
        "--allow-first-bootstrap",
        action="store_true",
        help="Permit proceeding when the status record file is absent, or present "
        "with a completely empty history for this environment — i.e. before the "
        "'write pending at promotion time' convention has ever applied at all. "
        "Never permits proceeding when the file/history exists but this exact "
        "releaseId is simply missing from it (a gap, not a fresh environment) — "
        "that always refuses regardless of this flag. Ordinary first deployments "
        "do NOT need this flag: they proceed via the sole-pending-entry rule "
        "below once the promotion PR has written their pending entry.",
    )
    parser.add_argument(
        "--claims-dir",
        default=None,
        help="Optional defense-in-depth check: if given, and "
        "gitops_release_attempt_claim.py has an outstanding (unconsumed) claim "
        "for this exact (environment, releaseId), refuse with exit 6 even if the "
        "outcome-based checks below would otherwise proceed. Does not replace the "
        "caller's own obligation to call 'claim' before deploying.",
    )
    args = parser.parse_args(argv)

    try:
        release_record = load_yaml(args.release_record)
    except FileNotFoundError:
        print(f"REFUSE: release record not found: {args.release_record}", file=sys.stderr)
        return 4

    if not isinstance(release_record, dict) or "releaseId" not in release_record or "environment" not in release_record:
        print("REFUSE: release record missing required fields (environment, releaseId)", file=sys.stderr)
        return 4

    environment = release_record["environment"]
    current_release_id = release_record["releaseId"]

    if args.claims_dir:
        # Matches gitops_release_attempt_claim.py's own claim_path() naming
        # exactly (environment__releaseId.claim) — this is a read of that same
        # claim file, not a second independent locking scheme.
        claim_file = Path(args.claims_dir) / f"{environment}__{current_release_id}.claim"
        if claim_file.exists():
            print(
                f"REFUSE: an attempt claim already exists for environment "
                f"'{environment}' releaseId '{current_release_id}' at {claim_file} "
                "— a deployment attempt for this exact releaseId is already in "
                "flight or crashed before being consumed. This predicate cannot "
                "by itself prove nothing has run; resolve via the recovery "
                "runbook's bootstrap-after-failure procedure before retrying.",
                file=sys.stderr,
            )
            return 6

    try:
        status_record = load_yaml(args.status_record)
        status_file_exists = True
    except FileNotFoundError:
        status_record = None
        status_file_exists = False

    if not status_file_exists:
        if args.allow_first_bootstrap:
            print(
                f"PROCEED: no status record exists for environment '{environment}' and "
                "--allow-first-bootstrap was passed; treating this as a verified first-ever "
                "bootstrap.",
            )
            return 0
        print(
            f"REFUSE: no status record found for environment '{environment}' "
            f"({args.status_record}). Missing evidence never proceeds by default; pass "
            "--allow-first-bootstrap only for a verified, genuinely first-ever bootstrap.",
            file=sys.stderr,
        )
        return 3

    if not isinstance(status_record, dict) or status_record.get("environment") != environment:
        print(
            "REFUSE: status record is malformed or its environment does not match the "
            f"release record's environment ('{environment}')",
            file=sys.stderr,
        )
        return 4

    history = status_record.get("history") or []
    if not isinstance(history, list):
        print("REFUSE: status record 'history' is malformed (not a list)", file=sys.stderr)
        return 4

    if not history:
        if args.allow_first_bootstrap:
            print(
                f"PROCEED: environment '{environment}' has an empty release-outcome history and "
                "--allow-first-bootstrap was passed; treating this as a verified first-ever "
                "bootstrap.",
            )
            return 0
        print(
            f"REFUSE: environment '{environment}' has an empty release-outcome history. Missing "
            "evidence never proceeds by default; pass --allow-first-bootstrap only for a "
            "verified, genuinely first-ever bootstrap.",
            file=sys.stderr,
        )
        return 3

    matching = [entry for entry in history if entry.get("releaseId") == current_release_id]
    if not matching:
        # Deliberately NOT covered by --allow-first-bootstrap: a non-empty history with
        # this exact releaseId missing is a gap in the record, not a fresh environment.
        print(
            f"REFUSE: no release-outcome entry for releaseId '{current_release_id}' in "
            f"environment '{environment}'. A non-empty history with this releaseId absent is "
            "treated as a recording gap, never as approval — --allow-first-bootstrap does not "
            "apply here.",
            file=sys.stderr,
        )
        return 3

    entry = matching[-1]
    outcome = entry.get("outcome")
    if outcome not in KNOWN_OUTCOMES:
        print(
            f"REFUSE: release-outcome entry for '{current_release_id}' has an unrecognized "
            f"outcome value: {outcome!r}",
            file=sys.stderr,
        )
        return 4

    if outcome == "healthy":
        print(f"PROCEED: releaseId '{current_release_id}' is recorded healthy in environment '{environment}'.")
        return 0

    if outcome == "rejected":
        classification = entry.get("classification", "unspecified")
        print(
            f"REFUSE: releaseId '{current_release_id}' is recorded REJECTED "
            f"(classification: {classification}) in environment '{environment}'. The release "
            "record must be updated to a different, healthy releaseId via a reviewed "
            "Git-repair PR before bootstrap may proceed. supersededBy is audit metadata only "
            "and does not authorize proceeding with THIS releaseId.",
            file=sys.stderr,
        )
        return 1

    if outcome == "unknown":
        print(
            f"REFUSE: releaseId '{current_release_id}' is recorded UNKNOWN (an attempt was made "
            f"but its outcome was never durably confirmed) in environment '{environment}'. This "
            "is never eligible for the first-attempt bypass — something already happened and its "
            "result is uncertain. Requires an explicit, reviewed determination before proceeding.",
            file=sys.stderr,
        )
        return 5

    # outcome == "pending"
    if len(matching) == 1:
        print(
            f"PROCEED: releaseId '{current_release_id}' is PENDING as the sole, first-ever "
            f"entry recorded for it in environment '{environment}' — the reviewed promotion PR "
            "that wrote this entry is the explicit approval to attempt it; there is nothing "
            "further to confirm before a first attempt.",
        )
        return 0

    print(
        f"REFUSE: releaseId '{current_release_id}' is PENDING but has {len(matching)} recorded "
        f"entries in environment '{environment}', not a sole first-ever entry — this looks like "
        "a replay of something already attempted (e.g. re-approving a previously-rejected "
        "releaseId instead of promoting a genuinely new one), which real recovery never does. "
        "Refusing rather than treating a repeated pending entry as fresh approval.",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
