#!/usr/bin/env python3
"""Local, no-cluster regression tests for scripts/gitops_release_attempt_claim.py
(GO-1 Gate 6a durable first-attempt claim). Reproduces the exact gap Codex's third
GO-1 review found (docs/PROGRESS.md session log 2026-09-09T14:37:25-06:00): running
the read-only bootstrap-precondition checker twice against the same sole-pending
fixture returns 0 both times, which is correct for a read-only predicate but is not
proof nothing has run — a crash between "checked" and "deployed" is indistinguishable
from never having tried. This suite proves the SEPARATE claim primitive added to
close that gap: a fresh claim succeeds; a second concurrent claim for the same
(environment, releaseId) refuses; a simulated crash (claim acquired, never consumed)
still refuses on retry, exactly reproducing and then closing Codex's repro; consuming
without a prior claim is refused (ordering violation); and a claim can be
legitimately reacquired only after a proper consume.

Runs the real script as a subprocess (black-box) against a real temp directory.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPT = REPO_ROOT / "scripts" / "gitops_release_attempt_claim.py"

failures = []


def check(desc, condition):
    if condition:
        print(f"PASS: {desc}")
    else:
        print(f"FAIL: {desc}")
        failures.append(desc)


def run(*args):
    result = subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True, text=True,
    )
    return result.returncode, result.stdout, result.stderr


def main():
    with tempfile.TemporaryDirectory() as td:
        claims_dir = str(Path(td) / "claims")

        # --- Fresh claim succeeds. ---
        rc, out, err = run("claim", "--claims-dir", claims_dir, "--environment", "dev", "--release-id", "dev-0001")
        check("fresh claim: exit 0", rc == 0)
        check("fresh claim: stdout confirms CLAIMED", "CLAIMED" in out)
        check("fresh claim: claim file actually exists on disk", (Path(claims_dir) / "dev__dev-0001.claim").exists())

        # --- CODEX'S EXACT REPRO, now closed: a second attempt against the SAME ---
        # --- (environment, releaseId) — modeling both a genuinely concurrent ---
        # --- caller AND a crash-then-retry, since a claim file cannot distinguish ---
        # --- the two, by design — must refuse, not silently proceed a second time. ---
        rc, out, err = run("claim", "--claims-dir", claims_dir, "--environment", "dev", "--release-id", "dev-0001")
        check("CONCURRENT/CRASH REPRO CLOSED: second claim for same (env, releaseId) refuses (exit 1)", rc == 1)
        check("second claim: stderr explains concurrent-or-crashed and names the recovery path", "concurrent attempt" in err and "recovery runbook" in err)
        check("second claim: stderr surfaces the existing claim's contents for diagnosis", "claimedAt" in err)

        # --- A DIFFERENT releaseId in the SAME environment is a genuinely fresh, ---
        # --- independent claim — must not collide with dev-0001's claim above. ---
        rc, out, err = run("claim", "--claims-dir", claims_dir, "--environment", "dev", "--release-id", "dev-0002")
        check("different releaseId, same environment: independent claim succeeds", rc == 0)

        # --- The SAME releaseId in a DIFFERENT environment is also independent. ---
        rc, out, err = run("claim", "--claims-dir", claims_dir, "--environment", "staging", "--release-id", "dev-0001")
        check("same releaseId, different environment: independent claim succeeds", rc == 0)

        # --- Consuming a claim that was never acquired is an ordering violation. ---
        rc, out, err = run("consume", "--claims-dir", claims_dir, "--environment", "dev", "--release-id", "never-claimed")
        check("consume without prior claim: refuses (exit 1), ordering violation", rc == 1)
        check("consume without prior claim: stderr names it an ordering violation", "ordering violation" in err)

        # --- Proper lifecycle: consume the dev-0001 claim (simulating outcome ---
        # --- durably recorded), then a FRESH claim for the SAME (environment, ---
        # --- releaseId) is legitimately allowed again — consume, not mere time ---
        # --- passing, is what clears the way for a real subsequent attempt (e.g. ---
        # --- recovery minting the same releaseId again would still be refused by ---
        # --- Gate 6a's own replay rule; this just proves the claim layer itself ---
        # --- does not leave a permanent, unrecoverable lock behind). ---
        rc, out, err = run("consume", "--claims-dir", claims_dir, "--environment", "dev", "--release-id", "dev-0001")
        check("consume after real claim: exit 0", rc == 0)
        check("consume after real claim: claim file actually removed from disk", not (Path(claims_dir) / "dev__dev-0001.claim").exists())
        rc, out, err = run("claim", "--claims-dir", claims_dir, "--environment", "dev", "--release-id", "dev-0001")
        check("reclaim after proper consume: succeeds (exit 0), not permanently locked", rc == 0)

        # --- Consuming the SAME claim twice: the second consume is again an ---
        # --- ordering violation (nothing left to consume), not a silent no-op. ---
        rc, out, err = run("consume", "--claims-dir", claims_dir, "--environment", "dev", "--release-id", "dev-0001")
        check("first consume of reclaimed dev-0001: exit 0", rc == 0)
        rc, out, err = run("consume", "--claims-dir", claims_dir, "--environment", "dev", "--release-id", "dev-0001")
        check("double consume: second call refuses (exit 1), not a silent no-op", rc == 1)

    print()
    if not failures:
        print(f"ALL PASS ({len(failures)} failures)")
        return 0
    print(f"{len(failures)} assertion(s) FAILED")
    return 1


if __name__ == "__main__":
    sys.exit(main())
