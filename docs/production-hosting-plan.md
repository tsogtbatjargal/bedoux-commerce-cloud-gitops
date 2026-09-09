# bedoux.ca production-hosting assessment and implementation plan

Assessment date: 2026-09-08. Task: **PH-A — planning only**.
Owner authorized architecture options, cost comparison, a proposed ADR, and this plan.
No implementation, deployment, DNS change, or AWS resource mutation is authorized by this document.
Execution state belongs to [PROGRESS.md](PROGRESS.md). This is a separate proposed hosting track;
the completed [P0–P14 plan](IMPLEMENTATION-PLAN.md) remains historical.

## Recommendation

Launch a public, read-only catalog on **private S3 + CloudFront** first, with `bedoux.ca` as the
canonical address and `www.bedoux.ca` redirecting to it. Develop the transactional store separately.
This is a recommendation awaiting owner review, assuming a catalog is useful before checkout
exists and the existing USD 20/month account limit remains. No new subdomain is required.

If the first release must run the existing FastAPI/PostgreSQL application continuously, consider
the Lightsail alternative below. If it must accept real payments, first scope the commerce work;
hosting the present demo does not produce a transaction-ready store.

The proposed decision is [ADR 0025](decisions/0025-catalog-first-production-hosting.md).
It remains **Proposed**. Planning authorization does not accept it or change existing guardrails.

## What exists and what still needs work

| Area | Repository evidence | Consequence for hosting |
|---|---|---|
| Frontend | React/Vite catalog, detail, cart, and confirmation routes; `apps/web/src/api/client.ts` calls `/api` | Uploading the current build alone will leave catalog requests failing; a static catalog adapter is required for the recommended option |
| Backend/data | FastAPI, SQLAlchemy, PostgreSQL, migrations, and server-side pricing | Reusable for later commerce; no need to run the database for an exported public catalog |
| Ordering | `apps/api/app/routers/orders.py` has unauthenticated create/read endpoints; write kill switch defaults on in app configuration | Disable order UI and API exposure for catalog launch; UUID order IDs are not customer authorization |
| Request protection | `apps/api/app/main.py` checks declared Content-Length; source explicitly limits this to the demo | Dynamic hosting needs actual streamed-body limits and malformed-header tests at the public boundary |
| Local deployment | `docker-compose.yml` publishes database/API ports and contains development credentials | A public server needs a separate hardened profile; do not deploy this file unchanged |
| Delivery | PR validation, digest/signature verification, EKS OIDC deployment and Helm rollback | Reuse validation and artifact integrity; create a scoped hosting deployment path rather than dispatching `deploy-learning.yml` |
| Domain | ADR 0022 selects bedoux.ca and retires Shopify; checkpoint records persistent DNS/ACM and absent website aliases | Preserve delegation and unrelated records; current DNS/account state must be checked before any cutover |
| Security evidence | H4 records 54 unfixed API base-image package findings | Refresh scans before a dynamic launch; historical scan results are not a production risk acceptance |

This assessment inspected source and public vendor documentation only. It did not verify current
DNS, registrar settings, certificates, account inventory, quotas, or billing. Shopify subscription
cancellation is an owner/account task and is not inferred from DNS changes.

## Architecture options

| Option | Runtime and data | Reuse / operational work | Fit |
|---|---|---|---|
| A — static catalog (recommended) | CloudFront serves a private S3 REST origin containing versioned web assets, public catalog JSON and product images; no public API or database | Keep React components; implement a catalog adapter and content-release process; no server patching or DB recovery | Lowest recurring cost; product changes require a release; no checkout or private customer data |
| B — one Lightsail VM | TLS reverse proxy, existing web/API containers and PostgreSQL on one non-Spot VM; encrypted backup copies off the VM | Most application reuse; operator owns patching, secret handling, monitoring, backup and restore | Development/low-stakes dynamic site if owner accepts downtime; one failure takes down app and DB |
| C — Lightsail VM plus encrypted managed DB | Web/API on a VM; managed PostgreSQL on private connectivity; no public DB | Less DB maintenance; application hardening and restore proof still required | Higher recurring budget; a single app VM still prevents an HA claim |
| D — always-on EKS production target | Existing chart/delivery model plus production networking, replicated app, managed DB and backups | Strong platform reuse; largest infrastructure and operational footprint | Does not fit the current budget; completed learning drills do not establish production uptime |

Lightsail supports Canada Central; exact bundle/database availability still needs preflight.
[AWS region reference](https://docs.aws.amazon.com/lightsail/latest/userguide/understanding-regions-and-availability-zones-in-amazon-lightsail.html).
External hosting providers and a serverless API rewrite are outside this initial AWS-centered
comparison. Reopen that comparison if the owner prioritizes managed checkout or another provider.

## Monthly cost comparison

All figures are **USD before tax**, excluding registrar renewal, payment processing, paid CI,
support subscriptions and operator labor. These are planning models, not a current account quote.
No promotional account credits, three-month trials, or historical net-zero bills are deducted.
Use 730 hours for hourly services; recalculate for the actual calendar month before deployment.

Common modeled account allowance: **USD 2/month**, including the existing hosted zone, state
storage, ECR and miscellaneous persistent usage. This is a conservative placeholder, not a
measured September total; refresh the whole-account forecast before choosing a live configuration.
Do not add another hosted zone charge on top of this allowance.

| Option | Hosting calculation / basis | Modeled whole-account subtotal | USD 20 cap assessment |
|---|---|---:|---|
| A | CloudFront Free plan USD 0 + USD 1–3 allowance for S3 requests, releases/version retention and optional monitoring | **USD 3–5/month** including common USD 2 | Leaves room for tax, existing usage variance and a USD 5 safety reserve; conditional on plan eligibility/features |
| B | VM USD 12 + 30 GB-month retained snapshots × USD 0.05 = USD 1.50 + USD 1.50 backup/log allowance | **USD 17/month** including common USD 2 | Exceeds the existing USD 16 forecast stop threshold before tax/reserve; do not deploy under unchanged controls |
| C | VM USD 12 + encrypted standard DB USD 30 + USD 3 backup/log allowance | **USD 47/month** including common USD 2 | Requires a revised budget; not HA |
| D | EKS standard control plane alone: 730 × USD 0.10 = USD 73 | **More than USD 75/month** after common USD 2 and required workers/LB/DB/storage | Already disqualified before sizing the other services |

Published Lightsail inputs: the public-IPv4 Linux 2 GB bundle is USD 12/month; snapshots are
USD 0.05/GB-month. The USD 15 managed DB lacks data encryption; the encrypted standard tier is
USD 30. The 2 GB VM is a sizing hypothesis requiring load/memory tests, and snapshot retention
is total billed data, not merely one snapshot's nominal size.
[Lightsail pricing](https://aws.amazon.com/lightsail/pricing/).
EKS charges separately for workers and other AWS resources.
[EKS pricing](https://aws.amazon.com/eks/pricing/).

The CloudFront Free plan advertises USD 0/month, 5 GB of S3 storage credit, and no uptime SLA.
Its restrictions include no custom cache policies and no access logging; confirm our required
cache/security behavior fits before selecting it. No automatic paid-plan upgrade is proposed.
[CloudFront pricing](https://aws.amazon.com/cloudfront/pricing/).
Published Free allowances are 1M requests and 100 GB transfer monthly. Sustained excess usage can
affect delivery performance even without CDN overage charges. Bundled DNS must be associated
correctly; S3 storage credits do not make every origin/request/version charge free.
[Plan details](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/flat-rate-pricing-plan.html).

For conservative accounting, the common USD 2 allowance retains Route 53's USD 0.50 hosted-zone
charge even if a verified bundle later covers it. Standard DNS queries are USD 0.40/million;
eligible AWS alias queries have separate no-charge rules.
[Route 53 pricing](https://aws.amazon.com/route53/pricing/).
The USD 1–3 S3/operations line is an allowance rather than a regional unit-price quote: model
up to 1 GB total retained site data, 100,000 origin GETs, 10,000 writes and 10 releases monthly,
then price storage, requests and retained versions explicitly before deployment.
[S3 pricing categories](https://aws.amazon.com/s3/pricing/).

Option A's allowance is not a spending cap: origin requests, unrelated services, CI and registrar
costs can still grow. If eligibility or required features fail, return for a revised comparison;
do not silently substitute pay-as-you-go CDN pricing. The existing USD 16 forecast stop and
USD 20 hard limit remain in force, including tax/conversion treatment in
[cost-guardrails.md](cost-guardrails.md). Future learning sessions consume the same account budget.

## Proposed catalog design and operating contract

Use the existing Route 53 zone and apex/www naming. Store only public material in a dedicated
S3 bucket in `ca-central-1`, with Block Public Access enabled and a bucket policy limited to the
chosen CloudFront distribution through Origin Access Control. Use a REST origin, not an S3
website endpoint; the latter cannot use this OAC pattern.
[AWS S3-origin guidance](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html).

CloudFront viewer TLS requires an ACM certificate in `us-east-1`; the existing Canada Central
ALB certificate cannot be reused for that purpose. Keep the Canadian origin and request a narrow
region exception for the viewer certificate, alongside explicit acceptance of global CDN
caching of public content.
[CloudFront certificate requirements](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cnames-and-https-requirements.html).

Build a catalog-only frontend mode with validated, release-versioned JSON and local product
images. Search/filter/detail routes use that snapshot. Hide cart, checkout and order-confirmation
routes; no simulated successful order. Existing API mode stays covered by its current tests.
The first published products, branding and descriptions need owner content approval; synthetic
seed records must not be presented as real sale inventory.

Publish immutable release directories and keep two known-good releases, bounded by byte count
and retention policy. A single reviewed release selection serves HTML, JSON and hashed assets
consistently; existing clients must retain access to their older hashed assets. Define the exact
origin-path/cache policy during local implementation. Permit SPA rewrites only for known UI
paths; missing assets and `/api/*` must fail explicitly instead of returning index.html with 200.
Test expiry/invalidation behavior against the chosen plan's restrictions.

Use repository-bound OIDC for a separate publisher role with access only to the site prefix and
required distribution operations. Keep public runtime free of credentials and private data.
No SSH or EKS permissions belong in the catalog publisher. Inspect the pinned Terraform
provider's schema and current AWS support before promising full plan-subscription automation;
if a console-only operation remains, provide the owner a numbered checklist and record the
confirmed result before automation continues.

Proposed catalog recovery targets, subject to owner acceptance: restore a known-good content
release within 60 minutes of operator response; recover all published content from source and
retained artifacts (no customer writes). These are test targets, not an uptime SLA or staffed
24/7 response promise. Check public health after every release and at an agreed monitoring
interval, notify the owner on failure, and rehearse rollback before launch.

## Guardrail changes required before persistent hosting

The present session runbook requires same-day teardown and labels resources `environment=learning`.
It does not currently permit a persistent site bucket, CDN distribution or always-on server.
ADR 0025 proposes a narrow production-hosting policy; it cannot silently change these rules.

Before any live hosting work, review a separate change that defines the production tag value,
persistent allowlist, budget allocation, named operations owner, certificate/global-service region
exceptions and launch/recovery runbook. Keep `project=bedoux-commerce-cloud`. Preserve current
learning rules and their teardown helper; do not place production resources in its state or
prefixes. Use a separate Terraform root/backend key, with exactly one state owning each shared
DNS resource. Review any state/alias ownership transfer explicitly; two roots must never both
manage the same apex or www record. Keep existing validation/MX/TXT records and nameservers.

The first hosting session must have an independent alarm, a cutover cutoff, a reviewed exact
saved plan and an explicit retained-resource list. Failed launch means restore the previous
DNS/release state and remove only the newly authorized temporary resources. Successful launch
retains only the newly approved list. Never delete the zone while the registrar delegates to it.
No current instruction authorizes that future retention exception.

## Proposed implementation sequence — all steps NOT STARTED

These are candidate tasks, not activated phases. Activate one at a time after assessment review.
Estimates are focused engineering effort, excluding owner review, provider delays and content work.

| Task | Deliverable | Required acceptance evidence | Estimate |
|---|---|---|---|
| PH-1 — decision and operating policy | Confirm launch mode, budget, downtime tolerance and content owner; accept/revise ADR 0025; reconcile persistent-hosting runbook, tags, state ownership and cost controls | Owner decision recorded; no contradictory active guardrail; exact retention and recovery boundaries documented | 2–4 hours |
| PH-2 — local catalog release | Add static data adapter, catalog-only routes, approved sample content, reproducible build and release manifest | Local browser: search/detail/deep links work without API; no order controls or API calls (static asset/JSON requests are expected); missing asset/API requests fail; existing API-mode tests pass | 1–2 days |
| PH-3 — hosting and delivery code | Separate Terraform root, private origin, TLS/DNS definitions, narrow OIDC publisher, release/rollback and monitoring commands with help/dry-run | Offline validation and local fixtures prove narrow policies, route/cache behavior and release rollback; check provider support for selected pricing plan; review all proposed DNS ownership changes | 1–2 days |
| PH-4 — alarmed preview session | Fresh account/DNS/cost preflight, bounded saved plan, separate exact-plan apply approval, preview deployment | Direct S3 denied; HTTPS, headers, routing, catalog and monitoring pass; prior-release rollback timed; cost/retention inventory reconciled | Reserve up to 4 hours; stop by agreed cutoff |
| PH-5 — launch and handoff | Owner-approved content/domain cutover, apex/www checks, recovery drill and operator guide | Verify public DNS and TLS, redirect/path behavior, no checkout, known-good rollback, notification delivery and exact persistent allowlist; record first billing refresh after data settles | 2–4 hours plus billing observation |

PH-4 must approve a specific preview-hostname/TLS method before apply; it does not implicitly
create a staging subdomain. PH-5 needs separate cutover approval. Preserve prior website records
in a private rollback artifact; if aliases are still absent, record that absence as the rollback
state rather than assuming a live Shopify site exists.

If the owner selects B/C, replace PH-2–PH-5 with a reviewed dynamic-hosting plan before activation:
private DB ports, non-development secrets, TLS renewal, scoped image retrieval without long-lived
AWS keys on the VM, patch/reboot procedure, measured sizing, encrypted off-host DB backups and
tested restore. For B, propose RPO 24 hours and RTO 4 hours only for non-customer data; disk
snapshots alone do not prove application-consistent PostgreSQL recovery. Do not reuse static
recovery targets or infer database HA.

## Separate work required before real commerce

Real orders/payments require their own accepted scope and tests: checkout/payment-provider
selection, server-verified payment events, idempotency, inventory concurrency, customer/admin
authorization and order privacy, refunds/fulfillment, tax/shipping requirements, retention and
backup policy, abuse controls, and monitoring with an accountable operator. This assessment
does not choose a payment provider, specify legal policy, or authorize customer-data collection.

## Assessment acceptance and next decision

PH-A evidence consists of: source-grounded options and gaps, dated vendor sources and reproducible
cost arithmetic, Proposed ADR 0025, ordered tasks with local/live acceptance and rollback criteria,
consistent checkpoint links, and passing docs/whitespace checks. No live claim is required for
this planning deliverable.

Owner review should resolve the first-release scope (catalog or transactions), hosting option,
monthly whole-account budget, content readiness and acceptable operator response time. The next
eligible task is **PH-1**, only after explicit activation. Publishing/merging this assessment
does not activate PH-1 or authorize AWS work.
