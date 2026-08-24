# P12.1 Route 53 and ACM session

This runbook proves T-1201 for ADR 0022's `bedoux.ca` apex domain without starting EKS or
P12.2. It creates the apex hosted zone first, waits for the owner to replace the registrar's
current nameservers, then requests the regional ACM certificate. Do not run it until the P12.1
branch has passed review and merged.

## Hard prerequisites

Stop before AWS mutation unless the owner has explicitly confirmed all three statements:

1. The owner controls `bedoux.ca` at its registrar and can replace its authoritative
   nameservers.
2. Shopify is intentionally retired; replacing the current DNS delegation and allowing the
   existing Shopify apex/`www` records to disappear is approved.
3. The new `bedoux.ca` Route 53 hosted zone may remain as the P12 persistent allowlist resource
   at its understood recurring cost.

Never record registrar credentials, registrant contact data, an AWS account ID, or full
account-bearing ARNs. Terraform does not purchase, transfer, renew, or change registrar settings
for the domain. Shopify account cancellation is also outside this runbook.

## Time and cost boundary

Reserve a **three-hour session** and set an independent alarm for the end time before starting.
Allocate approximately 30 minutes for preflight and the hosted-zone plan, 75 minutes for
registrar delegation and DNS checks, 45 minutes for ACM's bounded validation wait, and 30 minutes
for evidence and closeout. Nameserver propagation can exceed the estimate; the alarm still ends
active work. If the hosted zone was approved as persistent, leave only that reviewed resource
and resume validation later rather than opening unrelated AWS infrastructure.

Current AWS pricing must be rechecked during preflight. At the 2026-08-23 review, the first 25
Route 53 hosted zones cost USD 0.50 each per month, charged when created and not prorated; AWS's
12-hour test grace avoids the hosted-zone charge if it is deleted within that window. A
non-exportable public ACM certificate used by an integrated Application Load Balancer has no
additional certificate fee. Domain registration/renewal is separate.

References:

- <https://aws.amazon.com/route53/pricing/>
- <https://aws.amazon.com/certificate-manager/pricing/>
- <https://docs.aws.amazon.com/acm/latest/userguide/dns-validation.html>

## 1. Open the bounded AWS session

Complete every **Before the session** item in [`aws-session.md`](aws-session.md), including:

- exact `bedoux-admin` identity and `ca-central-1` region checks;
- current budget/cost and clean-inventory review;
- current registrar control, Shopify-retirement, and hosted-zone-persistence confirmations;
- exact Terraform plans and rollback commands;
- the three-hour end time and independent operator alarm;
- `bedoux.ca` hosted zone as the only planned persistent exception.

Read-only DNS baseline:

```bash
dig +short NS bedoux.ca
dig +short A bedoux.ca
dig +short AAAA bedoux.ca
dig +short CNAME www.bedoux.ca
dig +short MX bedoux.ca
dig +short TXT bedoux.ca
```

The expected pre-cutover shape is the existing non-Route 53 delegation with Shopify-directed
apex and `www` answers and no MX or apex TXT answer, as observed on 2026-08-24. Stop if the
results differ. An unexpected mail or verification record must be understood and deliberately
migrated or retired before replacing the authoritative nameservers.

## 2. Create only the hosted zone

Copy `infra/terraform/terraform.tfvars.p12-tls.example` to the explicit temporary file
`/tmp/bedoux-p12-session.tfvars`. For this first plan, change only
`route53_acm_certificate_enabled` to `false`.

Initialize the documented S3 backend, then create and review a saved, module-scoped plan:

```bash
terraform -chdir=infra/terraform plan \
  -var-file=/tmp/bedoux-p12-session.tfvars \
  -target=module.route53_acm \
  -out=/tmp/bedoux-p12-zone.tfplan
terraform -chdir=infra/terraform show /tmp/bedoux-p12-zone.tfplan
```

The exact plan must add one public hosted zone named `bedoux.ca`, contain the standard project
tags, and contain no certificate, domain-registration, EKS, VPC, ALB, NAT, RDS, or unrelated
resource. Apply only the saved plan after owner review:

```bash
terraform -chdir=infra/terraform apply /tmp/bedoux-p12-zone.tfplan
terraform -chdir=infra/terraform output -json route53_name_servers
```

Do not paste the nameserver output into committed evidence.

## 3. Owner browser checklist: delegate the apex at the registrar

The owner performs this at the registrar; Codex does not use registrar credentials:

1. Sign in to the registrar account that controls `bedoux.ca`.
2. Open the domain's authoritative-nameserver settings, not its ordinary DNS-record editor.
3. Record the current nameserver set in temporary operator notes for rollback; do not commit
   registrar account details.
4. Choose the registrar option for custom nameservers and replace the current set with the exact
   four Route 53 nameservers from the Terraform output.
5. Confirm that Shopify is being retired and that existing apex/`www` records in the old DNS
   service are intentionally not copied.
6. Save and confirm the registrar accepted all four Route 53 nameservers.
7. Report only that delegation succeeded and its timestamp; do not share account or contact
   details.

Verify from the operator terminal until the public NS answer exactly matches the Terraform
output:

```bash
dig +short NS bedoux.ca
dig +short A bedoux.ca
dig +short CNAME www.bedoux.ca
```

The authoritative NS answer must exactly match Terraform output. The apex and `www` website
answers are expected to become empty until P12.2 adds ALB aliases; this is ADR 0022's deliberate
temporary no-site window, not a reason to recreate Shopify records. Do not request the
certificate before the Route 53 delegation is publicly visible.

## 4. Request and validate the certificate

Set `route53_acm_certificate_enabled = true` in `/tmp/bedoux-p12-session.tfvars`. Create and
review a new module-scoped plan:

```bash
terraform -chdir=infra/terraform plan \
  -var-file=/tmp/bedoux-p12-session.tfvars \
  -target=module.route53_acm \
  -out=/tmp/bedoux-p12-certificate.tfplan
terraform -chdir=infra/terraform show /tmp/bedoux-p12-certificate.tfplan
```

The plan must preserve the zone and add one non-exportable regional ACM certificate whose names
are exactly `bedoux.ca` and `www.bedoux.ca`, the required DNS validation records, and the
validation waiter. Apply only that saved plan. The Terraform waiter is capped at 45 minutes:

```bash
terraform -chdir=infra/terraform apply /tmp/bedoux-p12-certificate.tfplan
aws acm describe-certificate --profile bedoux-admin --region ca-central-1 \
  --certificate-arn "$(terraform -chdir=infra/terraform output -raw acm_certificate_arn)" \
  --query 'Certificate.{Status:Status,DomainName:DomainName,SubjectAlternativeNames:SubjectAlternativeNames,Type:Type}' \
  --output json
```

T-1201 passes only when the sanitized result reports `ISSUED`, primary domain `bedoux.ca`, the
two expected certificate names, and an Amazon-issued certificate. A pending or timed-out request
is not completion evidence.

## 5. Closeout or rollback

If T-1201 passes, record timestamps, sanitized certificate fields, the exact plan summary, the
hosted-zone persistence approval, current budget, and `AWS: Route 53 zone + ACM certificate` in
`docs/PROGRESS.md`. Remove the two saved plan files and ignored session variables file. P12.2
starts separately and creates the ALB plus apex/`www` aliases.

If persistence was not approved or the delegation must be rolled back, restore the registrar's
previous nameservers first and verify that public `bedoux.ca` NS answers no longer match the
Route 53 zone. Then review and apply a module-scoped destroy plan. Finish every teardown
inventory check in `aws-session.md`; never delete the apex zone while the registrar still
delegates to it.
