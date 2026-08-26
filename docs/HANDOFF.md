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

Current state as of 2026-08-26:
- P0-P11 are complete and gate-approved. P12 is active; P12.1/T-1201 is complete and published
  on `main` through PR #51. P12.2 is the single active item; P12.3 has not started.
- PR #50 passed all four checks in final run `32783233323` and merged to `main` as `b08f197`.
- PR #51 passed all four checks in run `32907691085` and merged the live P12.1/T-1201 evidence
  to `main` as `452b214`.
- Checkpoint PR #52 passed all four checks in run `32908011599` and merged as `184a916`; the
  focused `p12-2-https` branch starts from that exact `origin/main` commit.
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
- T-1201 passed. The exact owner-approved plan created two validation records and an Amazon-issued
  RSA-2048 ACM certificate in `ISSUED` state for exactly `bedoux.ca` and `www.bedoux.ca`. The
  apply channel ended while streaming record creation, so independent process, Terraform-state,
  Route 53, and ACM checks verified completion rather than inferring it.
- No temporary AWS resources are live. Persistent allowlist is the state bucket/history, two ECR
  repositories, six IAM roles/policies, GitHub OIDC provider, and the approved `bedoux.ca`
  hosted zone plus issued certificate/validation records. The 2026-08-25 closeout sweep was
  clean; budget actual was USD 4.87 of USD 20. Temporary plan/variables files are removed.
- P12.2 local implementation is published on `p12-2-https` from exact preparation commit
  `70fe3da`: an opt-in Helm TLS overlay creates HTTP
  80/HTTPS 443 with a 443 redirect and exact apex/`www` hosts. The ALB controller discovers the
  issued ACM certificate, so no full certificate ARN is committed or stored in GitHub.
- The Route 53/ACM module now has disabled-by-default apex/`www` alias records. A live session
  must discover the temporary ALB DNS name and canonical hosted zone ID, then review a separate
  2-create/0-change/0-destroy plan. The aliases are removed before ALB teardown.
- `docs/runbooks/p12-2-https-session.md` reserves four hours with 75 minutes for teardown and
  requires separate exact-plan approvals. `scripts/p12-tls-proof.sh` fail-closes unless both
  names have trusted HTTPS health and HTTP 301 redirects. T-1202 still requires a real browser.
- Credential-free Terraform validation, Helm lint/TLS render, workflow YAML parse, proof-helper
  syntax/help/dry-run, and `git diff --check` pass. No AWS command or public endpoint proof ran.
- PR #53 final head `f04462e` passed all four jobs in run `33006117123`, completed scoped
  technical review without a blocker, and merged to `main` as `775dfe1`. T-1202 is still
  deferred; no AWS session is open.

Next action:
1. The owner sets a fresh four-hour independent alarm and explicitly opens the P12.2 AWS session.
   Begin with read-only preflight and the exact temporary-infrastructure plan. Do not apply
   infrastructure or aliases without their separate exact saved-plan approvals.

Hard boundaries: USD 20/month; ca-central-1; bedoux-admin only; no NAT Gateway; same-day teardown;
never record account IDs, secrets, personal email addresses, or registrar details. No P12.2 AWS
mutation is authorized from this checkpoint.
```
