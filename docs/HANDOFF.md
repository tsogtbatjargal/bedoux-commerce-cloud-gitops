# Handoff

Everything above the fenced block is reference; **paste the fenced block below into a new
Claude Code / Codex / agent session** to continue this project. Regenerate this file at every
session closeout (`/closeout`).

---

```text
Continue bedoux-commerce-cloud from
/var/home/tsogtb/git-projects/bedoux/worktrees/bedoux-commerce-cloud/raspy-lantern/bedoux-commerce-cloud.

Start with START-HERE.md, AGENTS.md, and docs/PROGRESS.md. The progress file is authoritative.
Use the active worktree/branch recorded by Git; preserve unrelated changes.

Current state as of 2026-08-25:
- P0-P11 are complete and gate-approved. P12 is active; P12.1 is the single active item on branch
  `p12-1-live-route53-acm`. P12.2 and P12.3 have not started.
- PR #50 passed all four checks in final run `32783233323` and merged to `main` as `b08f197`.
- The owner corrected the target to the `bedoux.ca` apex and retired Shopify because of its
  recurring cost. Accepted ADR 0022 supersedes ADR 0021 and records the owned-domain path
  required by ADR 0014.
- The merged implementation and PR description match the `bedoux.ca` apex design and rollback
  boundary. The continuation branch starts from the verified merge commit.
- The local implementation adds a disabled-by-default `route53-acm` Terraform module, exact
  `bedoux.ca` + `www.bedoux.ca` profile, root outputs, CI profile validation, and
  `docs/runbooks/p12-1-domain-tls-session.md`.
- The module deliberately excludes registration, registrar settings, and Shopify cancellation.
  It stages the live work: apex hosted zone first, registrar nameserver replacement second, then
  the certificate after public Route 53 delegation is verified. ACM validation is capped at 45
  minutes; the runbook reserves a three-hour alarmed session.
- Terraform formatting and credential-free validation pass for the default, P11, and corrected
  P12 profiles; `make docs-check` and `git diff --check` pass. GitHub Actions run `32783233323`
  passed all four PR validation jobs at the published `bedoux.ca` head.
- The exact owner-approved hosted-zone plan created one tagged public `bedoux.ca` Route 53 zone.
  The owner replaced the GoDaddy delegation; the `.ca` parent, workstation resolver, Cloudflare,
  Google Public DNS, and Quad9 now return exactly its four Route 53 nameservers. Apex and `www`
  website answers are empty as expected during ADR 0022's accepted temporary no-site window.
- T-1201 is not complete. No ACM certificate exists yet. The prior alarmed session is closed;
  certificate planning and apply require a fresh three-hour alarm, repeated preflight, a new
  saved module-only plan, and separate owner approval of its exact hash.
- No temporary AWS resources are live. Persistent allowlist is the state bucket/history, two ECR
  repositories, six IAM roles/policies, GitHub OIDC provider, and the approved `bedoux.ca`
  hosted zone. The 2026-08-25 closeout sweep was clean; budget actual was USD 4.87 of USD 20.

Next action:
1. Schedule a fresh three-hour independent alarm, repeat the current pricing/budget/inventory
   preflight, then create and review the certificate-enabled module-only plan from
   `docs/runbooks/p12-1-domain-tls-session.md`. T-1201 requires ACM status `ISSUED`.

Hard boundaries: USD 20/month; ca-central-1; bedoux-admin only; no NAT Gateway; same-day teardown;
never record account IDs, secrets, personal email addresses, or registrar details. No ACM
mutation is authorized from this checkpoint.
```
