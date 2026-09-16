#!/usr/bin/env python3
"""GO-1 Gate 4b paired Rollout coordinator — local state-transition MODEL (design-
contract tooling; not wired into any live Rollout — GO-6 installs Argo Rollouts and
implements `gitops-paired-rollout-promote.sh` for real, reusing this decision
function rather than re-deriving it). No cluster, network or AWS access: Rollout
state here is a plain dict the caller supplies (from a real `kubectl argo rollouts
get rollout -o json` in GO-6, or a test fixture here).

Corrected per Codex's third GO-1 review (docs/PROGRESS.md session log
2026-09-09T14:37:25-06:00), two separate P1 findings:

1. "Sequential promote calls and matching step indices are not sufficient traffic
   evidence." `decide_action()` never treats "both step indices happen to match" as
   proof of anything by itself — every promotion decision requires a fresh
   `paired_check_passed` input (the caller's real, reused P13 paired health/routing
   check), and every DIVERGED/Degraded state is checked BEFORE step-index equality
   is ever consulted for anything.
2. "A crash/second-call failure can leave API ahead... does not preserve automatic
   stable-traffic restoration." `decide_action()` treats ANY divergence between
   api/web step indices, or either Rollout reporting Degraded, as ABORT_BOTH — it
   never resumes a partial promotion by blindly promoting the lagging side to catch
   up, because doing so would promote based on an UNVERIFIED post-crash state
   rather than a fresh paired-health observation.

Fencing: `acquire_lease()` models coordinator ownership using the same atomic
create-if-absent primitive as `gitops_release_attempt_claim.py`, but with a bounded
TTL and an explicit `holder_id` — this is deliberately NOT a one-shot claim (a
coordinator cycles repeatedly across many promote calls for one paired rollout), so
a lease can be legitimately RENEWED by its own current holder, and can be legitimately
STOLEN once expired (models a crashed coordinator process being superseded by a
fresh one after a bounded timeout) but never stolen while unexpired (models two
coordinator instances genuinely running concurrently — refused).

Real-cluster mapping (GO-6 implements, not built here): the paired health/routing
check reuses `scripts/p13-canary-gate.sh`, `scripts/p13-alb-pod-readiness-gate.sh`
and `scripts/p13-alb-reconciliation-gate.sh`, re-pointed at Rollout-managed
Services; for the Traefik router path (Gate 3's pin), the ALB-specific
reconciliation gate's TrafikService-weighted-routing counterpart is named here as
`scripts/p13-traefik-reconciliation-gate.sh` (design-specified, GO-6 implements —
validates `TraefikService.status`/`weighted.services[].weight` the way
`p13-alb-reconciliation-gate.sh` validates ALB target-group weighted
`forwardConfig`, since repointing Service names alone proves nothing about actual
traffic split). On any ABORT_BOTH, the caller's next step is the SAME drain
ordering already specified in docs/runbooks/gitops-recovery.md's "Failed canary:
traffic recovery first" section — stable traffic verified restored on BOTH api and
web before either candidate is scaled down/cleaned up; this model does not
reimplement that drain sequencing, it only decides WHEN to enter it.
"""
import argparse
import datetime
import json
import sys
from pathlib import Path

DEGRADED_PHASES = {"Degraded"}

# Actions decide_action() can return:
ABORT_BOTH = "ABORT_BOTH"
HOLD = "HOLD"
PROMOTE_API = "PROMOTE_API"
PROMOTE_WEB = "PROMOTE_WEB"
DONE = "DONE"


def decide_action(api_state, web_state, paired_check_passed, total_steps):
    """Pure decision function — no I/O. api_state/web_state:
    {"currentStepIndex": int, "phase": str}. Returns one of the action constants.
    """
    # --- Divergence / Degraded checks come FIRST, before anything else is ---
    # --- consulted, including whether the paired check passed. A crash that left ---
    # --- api ahead of web must abort both, never resume by promoting web to catch ---
    # --- up on unverified post-crash state. ---
    if api_state["phase"] in DEGRADED_PHASES or web_state["phase"] in DEGRADED_PHASES:
        return ABORT_BOTH
    if api_state["currentStepIndex"] != web_state["currentStepIndex"]:
        return ABORT_BOTH

    step = api_state["currentStepIndex"]
    if step >= total_steps:
        return DONE

    # --- Step indices match and neither is Degraded: this is NOT by itself proof ---
    # --- of anything about traffic — only a fresh paired health/routing check ---
    # --- (the caller's real, reused P13 tooling) may authorize a promotion. ---
    if not paired_check_passed:
        return HOLD

    return PROMOTE_API


def decide_after_api_promote(api_state, web_state, api_advanced, api_post_promote_healthy):
    """Called after the coordinator has issued `promote api` and re-queried its
    state. api_advanced: bool (did currentStepIndex actually increase). This is
    where "sequential promote calls... are not sufficient traffic evidence" is
    enforced directly: advancing the step index is necessary but NOT sufficient —
    api_post_promote_healthy (a fresh, real health/routing observation of the NEW
    step, not just "the API call to promote succeeded") is separately required
    before web is ever promoted to match.
    """
    if not api_advanced:
        return ABORT_BOTH
    if not api_post_promote_healthy:
        return ABORT_BOTH
    return PROMOTE_WEB


def lease_path(lease_dir: Path) -> Path:
    return lease_dir / "paired-rollout-coordinator.lease"


def acquire_lease(lease_dir: Path, holder_id: str, ttl_seconds: int, now=None):
    """Returns (True, None) on success, (False, reason) on refusal. Fencing model:
    - No lease file: acquire fresh.
    - Lease file exists, held by THIS holder_id, not expired: renew (legitimate —
      the same coordinator instance continuing its own cycle).
    - Lease file exists, held by a DIFFERENT holder_id, not expired: refuse (a
      genuinely concurrent second coordinator instance).
    - Lease file exists, expired (regardless of holder): may be taken over (models
      a crashed coordinator being superseded after a bounded timeout — the ONLY
      form of "takeover" this allows; an unexpired lease is never stolen).
    """
    lease_dir.mkdir(parents=True, exist_ok=True)
    path = lease_path(lease_dir)
    now = now or datetime.datetime.now(datetime.timezone.utc)
    if path.exists():
        try:
            existing = json.loads(path.read_text())
            expires_at = datetime.datetime.fromisoformat(existing["expiresAt"])
        except (json.JSONDecodeError, KeyError, ValueError):
            return False, f"lease file at {path} is unreadable/malformed; refusing to assume it is safe to steal"
        if expires_at > now and existing.get("holderId") != holder_id:
            return False, (
                f"lease held by '{existing.get('holderId')}' until {existing['expiresAt']}, "
                f"not expired — refusing concurrent coordinator instance '{holder_id}'"
            )
        # Either same holder renewing, or the lease has expired: proceed to write.
    expires_at = now + datetime.timedelta(seconds=ttl_seconds)
    path.write_text(json.dumps({"holderId": holder_id, "expiresAt": expires_at.isoformat()}))
    return True, None


def cmd_decide(args):
    api_state = {"currentStepIndex": args.api_step, "phase": args.api_phase}
    web_state = {"currentStepIndex": args.web_step, "phase": args.web_phase}
    action = decide_action(api_state, web_state, args.paired_check_passed, args.total_steps)
    print(action)
    return 0


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--api-step", type=int, required=True)
    parser.add_argument("--api-phase", required=True)
    parser.add_argument("--web-step", type=int, required=True)
    parser.add_argument("--web-phase", required=True)
    parser.add_argument("--total-steps", type=int, required=True)
    parser.add_argument("--paired-check-passed", action="store_true")
    args = parser.parse_args(argv)
    return cmd_decide(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
