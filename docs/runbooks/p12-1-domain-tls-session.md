# P12.1 Route 53 and ACM session

This runbook proves T-1201 for ADR 0021's `cloud.bedoux.com` child domain without starting EKS
or P12.2. It creates the child hosted zone first, waits for delegation from the existing parent
DNS service, then requests the regional ACM certificate. Do not run it until the P12.1 branch
has passed review and merged.

## Hard prerequisites

Stop before AWS mutation unless the owner has explicitly confirmed all three statements:

1. The owner controls the existing DNS for `bedoux.com` and can add an `NS` record for the
   `cloud` child domain.
2. The existing parent nameservers and Shopify-directed apex/`www` records will remain unchanged.
3. The new `cloud.bedoux.com` Route 53 hosted zone may remain as the P12 persistent allowlist
   resource at its understood recurring cost.

Never record DNS-provider credentials, registrant contact data, an AWS account ID, or full
account-bearing ARNs. Terraform does not manage the parent zone or purchase, transfer, or renew
the domain.

## Time and cost boundary

Reserve a **three-hour session** and set an independent alarm for the end time before starting.
Allocate approximately 30 minutes for preflight and the hosted-zone plan, 75 minutes for
child-zone delegation and DNS checks, 45 minutes for ACM's bounded validation wait, and 30
minutes for evidence and closeout. DNS propagation can exceed the estimate; the alarm still
ends active work. If the hosted zone was approved as persistent, leave only that reviewed
resource and resume validation later rather than opening unrelated AWS infrastructure.

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
- current parent DNS and child-delegation control confirmations;
- exact Terraform plans and rollback commands;
- the three-hour end time and independent operator alarm;
- `cloud.bedoux.com` hosted zone as the only planned persistent exception.

Read-only DNS baseline:

```bash
dig +short NS bedoux.com
dig +short A bedoux.com
dig +short CNAME www.bedoux.com
dig +short NS cloud.bedoux.com
dig +short A cloud.bedoux.com
```

The parent must still use its reviewed non-Route 53 delegation and Shopify-directed records. The
`cloud.bedoux.com` NS and address answers must be empty before first creation. Stop if the results
differ; never overwrite an unexplained child record.

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

The exact plan must add one public hosted zone named `cloud.bedoux.com`, contain the standard
project tags, and contain no certificate, domain-registration, EKS, VPC, ALB, NAT, RDS, or
unrelated resource. Apply only the saved plan after owner review:

```bash
terraform -chdir=infra/terraform apply /tmp/bedoux-p12-zone.tfplan
terraform -chdir=infra/terraform output -json route53_name_servers
```

Do not paste the nameserver output into committed evidence.

## 3. Owner browser checklist: delegate only the child domain

The owner performs this at the existing DNS provider; Codex does not use provider credentials:

1. Sign in to the DNS provider that currently hosts `bedoux.com`.
2. Open the DNS-record management page for `bedoux.com`; do not open or change the parent
   domain's authoritative-nameserver setting.
3. Add an `NS` record for host/name `cloud`, using the exact four Route 53 nameservers from the
   Terraform output. Depending on the provider, enter them as one four-value record or four NS
   records with the same host. Do not copy the surrounding JSON punctuation.
4. Leave the apex `A`/`AAAA`, `www` CNAME, parent `NS`, mail, verification, and all other records
   unchanged.
5. Save and confirm the DNS provider accepted all four child nameservers.
6. Report only that the child delegation succeeded and its timestamp; do not share account or
   contact details.

Verify from the operator terminal until the public answer exactly matches the Terraform output:

```bash
dig +short NS cloud.bedoux.com
dig +short NS bedoux.com
dig +short CNAME www.bedoux.com
```

The child NS answer must exactly match Terraform output, while the parent NS and Shopify `www`
answer remain unchanged. Do not request the certificate before both conditions pass.

## 4. Request and validate the certificate

Set `route53_acm_certificate_enabled = true` in `/tmp/bedoux-p12-session.tfvars`. Create and review a
new module-scoped plan:

```bash
terraform -chdir=infra/terraform plan \
  -var-file=/tmp/bedoux-p12-session.tfvars \
  -target=module.route53_acm \
  -out=/tmp/bedoux-p12-certificate.tfplan
terraform -chdir=infra/terraform show /tmp/bedoux-p12-certificate.tfplan
```

The plan must preserve the zone and add one non-exportable regional ACM certificate covering
exactly `cloud.bedoux.com` with no additional names, its DNS validation record, and the
validation waiter. Apply only that saved plan. The Terraform waiter is capped at 45 minutes:

```bash
terraform -chdir=infra/terraform apply /tmp/bedoux-p12-certificate.tfplan
aws acm describe-certificate --profile bedoux-admin --region ca-central-1 \
  --certificate-arn "$(terraform -chdir=infra/terraform output -raw acm_certificate_arn)" \
  --query 'Certificate.{Status:Status,DomainName:DomainName,SubjectAlternativeNames:SubjectAlternativeNames,Type:Type}' \
  --output json
```

T-1201 passes only when the sanitized result reports `ISSUED`, the expected two names, and an
Amazon-issued certificate. A pending or timed-out request is not completion evidence.

## 5. Closeout or rollback

If T-1201 passes, record timestamps, the sanitized certificate fields, the exact plan summary,
the hosted-zone persistence approval, current budget, and `AWS: Route 53 zone + ACM certificate`
in `docs/PROGRESS.md`. Remove the two saved plan files and ignored session variables file.
P12.2 starts separately and attaches the certificate to its temporary ALB.

If the owner did not approve persistence, or delegation must be rolled back, remove only the
`cloud.bedoux.com` NS record from the parent DNS first and verify that the public child NS answer
is empty. Then review and apply a module-scoped destroy plan. Finish every teardown inventory
check in `aws-session.md`; never delete the child zone while the parent still delegates to it.
