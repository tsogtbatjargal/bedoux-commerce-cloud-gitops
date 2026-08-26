# P12.2 custom-domain HTTPS session

This runbook proves T-1202 with the existing issued ACM certificate, one temporary ALB, and
Terraform-managed aliases for `bedoux.ca` and `www.bedoux.ca`. It does not recreate or replace
the P12.1 hosted zone or certificate.

The Helm overlay uses AWS Load Balancer Controller certificate discovery from the Ingress TLS
hosts. No full certificate ARN is committed or stored in GitHub. Terraform adds the aliases only
after the controller-created ALB reports a DNS name and canonical hosted zone ID, avoiding a
dependency cycle between Kubernetes and Route 53.

Controller behavior references:

- <https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/ingress/cert_discovery/>
- <https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/tasks/ssl_redirect/>
- <https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-to-elb-load-balancer.html>

## Time, cost, and approval boundary

Reserve a **four-hour session** with at least 75 minutes protected for alias removal and full
teardown. Set an independent operator alarm before any AWS mutation; at the alarm, stop evidence
work and begin teardown. Recheck current EKS, EC2, and ALB prices during preflight. The expected
temporary shape is one EKS control plane, one bounded Spot node, one internet-facing ALB, and the
existing no-NAT VPC. The approved persistent exceptions are the existing state/ECR/IAM/OIDC
allowlist plus the `bedoux.ca` zone, certificate, and validation records. The website aliases are
session-scoped because their ALB target is temporary.

No apply is authorized by this document or by P12.1 approval. Complete every preflight in
[`aws-session.md`](aws-session.md), review a saved plan, and obtain the owner's exact-plan
approval before each apply. Stop on an unexpected resource, NAT Gateway, replacement/deletion of
the hosted zone or certificate, unexplained DNS record, or insufficient teardown margin.

## 1. Local and live preflight

Before opening the session, the P12.2 branch must be merged to `main`, PR checks must pass, and
these local checks must be green:

```bash
terraform -chdir=infra/terraform fmt -check -recursive
terraform -chdir=infra/terraform validate -var=skip_aws_credentials_validation=true \
  -var-file=terraform.tfvars.p12-tls.example
helm lint charts/bedoux
helm template bedoux charts/bedoux \
  -f charts/bedoux/values-aws.yaml \
  -f charts/bedoux/values-aws-tls.yaml >/tmp/bedoux-p12-tls-rendered.yaml
scripts/p12-tls-proof.sh --dry-run
```

Inside the alarmed session, verify the exact `bedoux-admin` identity, `ca-central-1`, budget,
clean temporary-resource inventory, current public delegation, and the P12.1 certificate's
`ISSUED` state. Copy `infra/terraform/terraform.tfvars.p12-tls.example` to the ignored
`/tmp/bedoux-p12-session.tfvars`; keep `route53_aliases_enabled=false` for the infrastructure
plan. Initialize the documented S3 backend and reconcile the persistent imports without changing
AWS resources.

Build and review the normal saved session-infrastructure plan. It must preserve the Route 53/ACM
module, contain no DNS changes, create no NAT Gateway, and include only the expected temporary
VPC/EKS/add-on resources. Apply only its unchanged, owner-approved saved plan.

## 2. Create the HTTPS Ingress

Bootstrap the namespace, `gp3` StorageClass, and pinned AWS Load Balancer Controller exactly as
documented in [`p6-4-ci-deploy.md`](p6-4-ci-deploy.md). Dispatch **Deploy learning session** from
the merged `main` commit with:

- `seed_catalog=true` for the fresh in-cluster PostgreSQL volume;
- `use_custom_domain=true`;
- every RDS, S3, Secrets Manager, and rollback-drill input `false`.

The workflow adds `charts/bedoux/values-aws-tls.yaml`. The rendered Ingress must have exactly the
two certificate hosts, HTTP 80 and HTTPS 443 listeners, and a port-443 redirect. The controller's
existing scoped IAM policy permits only certificate list/describe discovery; it does not create
or replace the certificate. Before aliases exist, the workflow proves the trusted listener by
connecting to the discovered ALB while retaining `bedoux.ca` as TLS SNI and HTTP host.

Verify the workflow is green and inspect the live Ingress/controller events. Stop if certificate
discovery is ambiguous, the HTTPS listener is absent, or either target is unhealthy.

## 3. Add only the two Route 53 aliases

Discover the ALB values without recording them in committed evidence:

```bash
alb_dns_name="$(kubectl -n bedoux get ingress bedoux \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
test -n "$alb_dns_name"
read -r alias_dns_name alias_zone_id alb_state <<<"$(aws elbv2 describe-load-balancers \
  --profile bedoux-admin --region ca-central-1 \
  --query "LoadBalancers[?DNSName=='${alb_dns_name}'] | [0].[DNSName,CanonicalHostedZoneId,State.Code]" \
  --output text)"
test "$alias_dns_name" = "$alb_dns_name"
test "$alb_state" = "active"
```

Set only these three values in `/tmp/bedoux-p12-session.tfvars`:

```text
route53_aliases_enabled         = true
route53_alias_target_dns_name   = "<discovered ALB DNS name>"
route53_alias_target_zone_id    = "<discovered canonical hosted zone ID>"
```

Create a module-scoped saved plan and show it:

```bash
terraform -chdir=infra/terraform plan \
  -var-file=/tmp/bedoux-p12-session.tfvars \
  -target=module.route53_acm \
  -out=/tmp/bedoux-p12-aliases.tfplan
terraform -chdir=infra/terraform show /tmp/bedoux-p12-aliases.tfplan
```

The exact plan must be **2 creates, 0 changes, 0 destroys**: one `A` alias for `bedoux.ca` and one
for `www.bedoux.ca`, both targeting the same active ALB with target-health evaluation enabled.
It must preserve the zone, validation records, and certificate. Hash and apply only the exact
owner-approved saved plan.

## 4. Prove T-1202

Wait until independent public resolvers return addresses for both names, then run:

```bash
dig +short A bedoux.ca
dig +short A www.bedoux.ca
scripts/p12-tls-proof.sh --execute
```

The script requires trusted hostname-verified HTTPS health and an HTTP 301 redirect to HTTPS for
both names. Then open `https://bedoux.ca` in a real browser, confirm there is no certificate
warning, load the catalog, and record only the timestamp and result. T-1202 does not pass from a
Terraform apply or ALB status alone.

## 5. Remove aliases and tear down

Begin with at least 75 minutes remaining. Set `route53_aliases_enabled=false` in the temporary
variables file and create a new module-scoped saved plan. It must show exactly the two website
alias destroys and no change to the zone, certificate, or validation records. Apply only after
exact-plan approval, then verify the public website answers disappear.

Delete the Ingress and wait until its ALB and target groups are gone before removing the release,
namespace, controller, and cluster. Run the guarded session destroy and every inventory check in
`aws-session.md`. The final state may retain only the approved persistent allowlist; no alias may
remain pointing at the deleted ALB.

Remove `/tmp/bedoux-p12-tls-rendered.yaml`, `/tmp/bedoux-p12-session.tfvars`, and both saved plan
files. Record the workflow run, sanitized listener/redirect/browser proof, alias create/remove
plan summaries, timestamps, cost, and clean sweep in `docs/PROGRESS.md`. P12.3 separately records
the final zone/certificate persistence evidence and phase teardown gate.
