#!/usr/bin/env python3
"""Local, no-cluster regression tests for
scripts/gitops_bootstrap_precondition_check.py (GO-1 Gate 6a). Reproduces the exact
defect Codex's GO-1 review found (docs/PROGRESS.md session log
2026-09-09T11:03:16-06:00): a release record whose releaseId is still a REJECTED
one must be refused even if some later releaseId in the same history is healthy.
Runs the real script as a subprocess (black-box) against real temp YAML files.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPT = REPO_ROOT / "scripts" / "gitops_bootstrap_precondition_check.py"
FIXTURE_STATUS = REPO_ROOT / "docs" / "gitops-fixtures" / "dev-status.example.yaml"

failures = []


def check(desc, condition):
    if condition:
        print(f"PASS: {desc}")
    else:
        print(f"FAIL: {desc}")
        failures.append(desc)


def run(release_record_path, status_record_path, extra_args=()):
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--release-record", str(release_record_path),
         "--status-record", str(status_record_path), *extra_args],
        capture_output=True, text=True,
    )
    return result.returncode, result.stdout, result.stderr


def write_release_record(directory, release_id, environment="dev"):
    path = directory / f"release-{release_id}.yaml"
    path.write_text(f"environment: {environment}\nreleaseId: \"{release_id}\"\n")
    return path


def main():
    with tempfile.TemporaryDirectory() as td:
        d = Path(td)

        # --- The exact bug Codex found: rejected releaseId must refuse, even ---
        # --- though a later releaseId in the same history is healthy. ---
        rejected_record = write_release_record(d, "dev-0001")
        rc, out, err = run(rejected_record, FIXTURE_STATUS)
        check("BUG REPRO: releaseId dev-0001 (rejected, superseded by healthy dev-0002) is REFUSED",
              rc == 1)
        check("rejected case: exit code is exactly 1 (not some other refuse code)", rc == 1)
        check("rejected case: stderr names the classification", "migration-failure" in err)
        check("rejected case: stderr explains supersededBy does not authorize this releaseId",
              "does not authorize" in err)

        healthy_record = write_release_record(d, "dev-0002")
        rc, out, err = run(healthy_record, FIXTURE_STATUS)
        check("CORRECTED positive: releaseId dev-0002 (actually healthy) PROCEEDS", rc == 0)

        # --- FIRST-BOOTSTRAP CONTRADICTION, corrected per Codex's second review: a ---
        # --- pending entry that is the SOLE entry ever recorded for a releaseId is ---
        # --- an approved first attempt and must PROCEED, not refuse. This is the ---
        # --- normal case for any brand-new environment's first-ever release, since ---
        # --- the design has every promotion write pending in the same PR. ---
        first_attempt_status = d / "first-attempt-status.yaml"
        first_attempt_status.write_text(
            "environment: dev\n"
            "history:\n"
            "  - releaseId: \"dev-0003\"\n"
            "    outcome: pending\n"
        )
        first_attempt_record = write_release_record(d, "dev-0003")
        rc, out, err = run(first_attempt_record, first_attempt_status)
        check("CONTRADICTION FIXED: sole/first-ever pending entry PROCEEDS (exit 0), without needing --allow-first-bootstrap",
              rc == 0)
        check("approved-first-attempt: stdout explains the reviewed-PR rationale",
              "explicit approval" in out)

        # --- A pending entry that is NOT the sole entry for its releaseId (a ---
        # --- replay/re-approval attempt, distinct from a fresh first attempt) ---
        # --- must still refuse, with its own distinct exit code (2). ---
        replay_status = d / "replay-status.yaml"
        replay_status.write_text(
            "environment: dev\n"
            "history:\n"
            "  - releaseId: \"dev-0004\"\n"
            "    outcome: rejected\n"
            "    classification: migration-failure\n"
            "  - releaseId: \"dev-0004\"\n"
            "    outcome: pending\n"
        )
        replay_record = write_release_record(d, "dev-0004")
        rc, out, err = run(replay_record, replay_status)
        check("pending replay (same releaseId re-approved after a prior entry): refuses with exit 2, distinct from rejected (1)",
              rc == 2)
        check("pending replay: stderr explains this is not a sole first-ever entry",
              "not a sole first-ever entry" in err)

        # --- unknown outcome always refuses, never eligible for any bypass, even ---
        # --- as a sole entry (distinguishes "never attempted" from "attempted, ---
        # --- outcome uncertain"). ---
        unknown_status = d / "unknown-status.yaml"
        unknown_status.write_text(
            "environment: dev\n"
            "history:\n"
            "  - releaseId: \"dev-0005\"\n"
            "    outcome: unknown\n"
        )
        unknown_record = write_release_record(d, "dev-0005")
        rc, out, err = run(unknown_record, unknown_status)
        check("unknown outcome (sole entry): refuses with its own exit code 5, not treated as approved-first-attempt",
              rc == 5)
        rc, out, err = run(unknown_record, unknown_status, extra_args=["--allow-first-bootstrap"])
        check("unknown outcome: --allow-first-bootstrap does not create a bypass either",
              rc == 5)

        # --- missing entry in a non-empty history refuses, no override loophole ---
        gap_record = write_release_record(d, "dev-9999")
        rc, out, err = run(gap_record, FIXTURE_STATUS)
        check("missing entry (non-empty history): refuses with exit 3", rc == 3)
        rc, out, err = run(gap_record, FIXTURE_STATUS, extra_args=["--allow-first-bootstrap"])
        check("missing entry: --allow-first-bootstrap does NOT create a loophole (still exit 3)",
              rc == 3)

        # --- status file entirely missing: refuses by default, allowed only with ---
        # --- explicit --allow-first-bootstrap ---
        missing_status = d / "does-not-exist.yaml"
        fresh_record = write_release_record(d, "dev-0001", environment="staging")
        rc, out, err = run(fresh_record, missing_status)
        check("missing status file: refuses by default with exit 3", rc == 3)
        rc, out, err = run(fresh_record, missing_status, extra_args=["--allow-first-bootstrap"])
        check("missing status file: proceeds (exit 0) only with explicit --allow-first-bootstrap",
              rc == 0)

        # --- empty history for the environment: same first-bootstrap rule ---
        empty_status = d / "empty-history.yaml"
        empty_status.write_text("environment: staging\nhistory: []\n")
        rc, out, err = run(fresh_record, empty_status)
        check("empty history: refuses by default with exit 3", rc == 3)
        rc, out, err = run(fresh_record, empty_status, extra_args=["--allow-first-bootstrap"])
        check("empty history: proceeds (exit 0) with --allow-first-bootstrap", rc == 0)

        # --- malformed outcome value refuses distinctly (exit 4) ---
        malformed_status = d / "malformed.yaml"
        malformed_status.write_text(
            "environment: dev\n"
            "history:\n"
            "  - releaseId: \"dev-weird\"\n"
            "    outcome: something-unrecognized\n"
        )
        weird_record = write_release_record(d, "dev-weird")
        rc, out, err = run(weird_record, malformed_status)
        check("malformed outcome value: refuses with exit 4", rc == 4)

        # --- CODEX'S THIRD-REVIEW EXACT REPRO, now closed: running the read-only ---
        # --- checker twice against the same sole-pending fixture, with a claim ---
        # --- (scripts/gitops_release_attempt_claim.py) acquired in between as a ---
        # --- real caller would, must now diverge on the second call instead of ---
        # --- returning 0 both times. ---
        claims_dir = d / "claims"
        claim_script = REPO_ROOT / "scripts" / "gitops_release_attempt_claim.py"
        rc, out, err = run(
            first_attempt_record, first_attempt_status,
            extra_args=["--claims-dir", str(claims_dir)],
        )
        check("claims-dir given, no claim yet: first check still proceeds (exit 0)", rc == 0)
        claim_rc = subprocess.run(
            [sys.executable, str(claim_script), "claim", "--claims-dir", str(claims_dir),
             "--environment", "dev", "--release-id", "dev-0003"],
            capture_output=True, text=True,
        ).returncode
        check("real caller acquires the claim after the first check (as documented sequence requires)", claim_rc == 0)
        rc, out, err = run(
            first_attempt_record, first_attempt_status,
            extra_args=["--claims-dir", str(claims_dir)],
        )
        check("REPRO CLOSED: second check with an outstanding unconsumed claim now refuses (exit 6), no longer identical to the first",
              rc == 6)
        check("outstanding-claim refusal: stderr names the claim path and says this predicate cannot prove nothing has run",
              "cannot by itself prove nothing has run" in err)
        # Without --claims-dir the read-only outcome logic is unchanged (still 0) —
        # this flag is additive, never a behavior change for callers that omit it.
        rc, out, err = run(first_attempt_record, first_attempt_status)
        check("omitting --claims-dir: read-only predicate behavior is unchanged (still exit 0)", rc == 0)

        # --- environment mismatch between release record and status record refuses ---
        mismatched_env_record = write_release_record(d, "dev-0002", environment="staging")
        rc, out, err = run(mismatched_env_record, FIXTURE_STATUS)
        check("environment mismatch (release record says staging, status file says dev): refuses with exit 4",
              rc == 4)

    print()
    if not failures:
        print(f"ALL PASS ({len(failures)} failures)")
        return 0
    print(f"{len(failures)} assertion(s) FAILED")
    return 1


if __name__ == "__main__":
    sys.exit(main())
