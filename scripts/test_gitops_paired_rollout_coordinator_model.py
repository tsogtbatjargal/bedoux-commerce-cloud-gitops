#!/usr/bin/env python3
"""Local, no-cluster regression tests for
scripts/gitops_paired_rollout_coordinator_model.py (GO-1 Gate 4b). Proves the two
P1 gaps from Codex's third GO-1 review (docs/PROGRESS.md session log
2026-09-09T14:37:25-06:00) are closed at the decision-model level: (1) matching
step indices / a successful promote call are never treated as sufficient traffic
evidence by themselves, and (2) a crash/second-call failure that leaves api ahead
of web is aborted, never resumed by blindly promoting web to catch up. Also proves
the fencing/lease model's concurrent-instance-refusal and crash-then-takeover
behavior. Imports the module directly (pure functions, no subprocess needed for the
decision logic); uses real temp directories for the lease file tests.
"""
import datetime
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))
import gitops_paired_rollout_coordinator_model as m  # noqa: E402

failures = []


def check(desc, condition):
    if condition:
        print(f"PASS: {desc}")
    else:
        print(f"FAIL: {desc}")
        failures.append(desc)


def main():
    # --- Matched, healthy, paired check FAILS: holds, never promotes on step- ---
    # --- index equality alone. ---
    api = {"currentStepIndex": 1, "phase": "Paused"}
    web = {"currentStepIndex": 1, "phase": "Paused"}
    check("matched steps + failed paired check: HOLD, not PROMOTE (step-index equality is not sufficient traffic evidence)",
          m.decide_action(api, web, paired_check_passed=False, total_steps=5) == m.HOLD)

    # --- Matched, healthy, paired check PASSES: promotes api first. ---
    check("matched steps + passed paired check: PROMOTE_API (api always promotes first)",
          m.decide_action(api, web, paired_check_passed=True, total_steps=5) == m.PROMOTE_API)

    # --- CODEX'S EXACT GAP #2, CLOSED: api ahead of web (a crash between the two ---
    # --- promote calls) must ABORT BOTH, never resume by blindly promoting web. ---
    api_ahead = {"currentStepIndex": 2, "phase": "Paused"}
    web_behind = {"currentStepIndex": 1, "phase": "Paused"}
    check("CRASH REPRO CLOSED: api ahead of web (diverged step indices) -> ABORT_BOTH, regardless of paired-check result",
          m.decide_action(api_ahead, web_behind, paired_check_passed=True, total_steps=5) == m.ABORT_BOTH)
    check("diverged step indices still ABORT_BOTH even when paired check failed too (not double-counted, still the same action)",
          m.decide_action(api_ahead, web_behind, paired_check_passed=False, total_steps=5) == m.ABORT_BOTH)

    # --- Either side Degraded (independent pod crash unrelated to the ---
    # --- coordinator) -> ABORT_BOTH, checked BEFORE step-index/paired-check logic. ---
    api_degraded = {"currentStepIndex": 1, "phase": "Degraded"}
    web_ok = {"currentStepIndex": 1, "phase": "Paused"}
    check("api Degraded (matched step index otherwise) -> ABORT_BOTH", m.decide_action(api_degraded, web_ok, True, 5) == m.ABORT_BOTH)
    web_degraded = {"currentStepIndex": 1, "phase": "Degraded"}
    check("web Degraded (matched step index otherwise) -> ABORT_BOTH", m.decide_action(api, web_degraded, True, 5) == m.ABORT_BOTH)

    # --- Both at the final step: DONE, not an endless PROMOTE loop. ---
    api_done = {"currentStepIndex": 5, "phase": "Paused"}
    web_done = {"currentStepIndex": 5, "phase": "Paused"}
    check("both at total_steps: DONE", m.decide_action(api_done, web_done, True, 5) == m.DONE)

    # --- CODEX'S EXACT GAP #1, CLOSED: after promoting api, "the call succeeded ---
    # --- and the step index advanced" is NOT sufficient — a fresh post-promote ---
    # --- health observation is separately required before web is promoted to match. ---
    check("api promote call advanced the step index BUT post-promote health check failed: ABORT_BOTH, not PROMOTE_WEB",
          m.decide_after_api_promote(api, web, api_advanced=True, api_post_promote_healthy=False) == m.ABORT_BOTH)
    check("api promote call did NOT advance the step index at all (a failed/no-op promote): ABORT_BOTH",
          m.decide_after_api_promote(api, web, api_advanced=False, api_post_promote_healthy=True) == m.ABORT_BOTH)
    check("api promote call advanced AND post-promote health passed: PROMOTE_WEB (only now is web promoted to match)",
          m.decide_after_api_promote(api, web, api_advanced=True, api_post_promote_healthy=True) == m.PROMOTE_WEB)

    # --- Fencing / lease model. ---
    with tempfile.TemporaryDirectory() as td:
        lease_dir = Path(td)
        ok, reason = m.acquire_lease(lease_dir, holder_id="coordinator-a", ttl_seconds=60)
        check("fresh lease: acquired", ok)

        ok2, reason2 = m.acquire_lease(lease_dir, holder_id="coordinator-b", ttl_seconds=60)
        check("CONCURRENT COORDINATOR REFUSED: a second, different holder cannot acquire an unexpired lease", ok2 is False)
        check("concurrent-coordinator refusal: reason names the current holder", "coordinator-a" in (reason2 or ""))

        ok3, reason3 = m.acquire_lease(lease_dir, holder_id="coordinator-a", ttl_seconds=60)
        check("same holder renewing its own unexpired lease: succeeds (not treated as a concurrent conflict)", ok3)

        # Simulate a crashed coordinator: write an already-expired lease directly,
        # then prove a FRESH holder can take over (bounded-timeout supersession),
        # while an unexpired one (above) could not be stolen.
        expired_path = m.lease_path(lease_dir)
        past = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=5)
        expired_path.write_text(f'{{"holderId": "coordinator-a", "expiresAt": "{past.isoformat()}"}}')
        ok4, reason4 = m.acquire_lease(lease_dir, holder_id="coordinator-c", ttl_seconds=60)
        check("CRASH TAKEOVER: a fresh holder CAN acquire an EXPIRED lease left by a crashed coordinator", ok4)

    print()
    if not failures:
        print(f"ALL PASS ({len(failures)} failures)")
        return 0
    print(f"{len(failures)} assertion(s) FAILED")
    return 1


if __name__ == "__main__":
    sys.exit(main())
