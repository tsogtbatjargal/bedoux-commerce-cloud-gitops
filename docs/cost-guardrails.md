# Cost guardrails

## Limit

The target is **USD 20 per calendar month**, including taxes and currency
conversion where applicable. Treat AWS usage data as delayed rather than a
real-time spending control.

## Allocation

| Category | Monthly target |
|---|---:|
| EKS control-plane session hours | USD 5 |
| ALB and light processing | USD 3 |
| Spot worker-node session hours | USD 4 |
| Short-lived RDS exercises | USD 2 |
| S3, ECR, logs, DNS, and miscellaneous | USD 1 |
| Safety buffer | USD 5 |

These are guardrails, not pricing guarantees. A session requires a current
regional estimate before it begins.

## Billing controls

Configure:

- a monthly cost budget at USD 20;
- actual-cost notifications at USD 5, USD 10, USD 16, and USD 20;
- a forecasted-cost notification at USD 16;
- Cost Anomaly Detection with email notification;
- cost-allocation tags for project and environment;
- short CloudWatch log retention.

## Prohibited in the learning profile

- a continuously running EKS cluster;
- an EKS version in extended support;
- NAT Gateway without a reviewed cost exception;
- multiple ALBs when path routing can share one;
- provisioned-throughput or reserved-capacity features;
- Multi-AZ RDS during routine learning sessions;
- indefinite snapshots, unattached EBS volumes, or unused public IPv4
  addresses;
- unbounded node or pod autoscaling.

## Persistent-resource allowlist

Only these may remain after a session, once their cost is understood:

- Terraform state bucket and state history;
- small ECR image repositories with lifecycle rules;
- small S3 product-asset bucket;
- Route 53 hosted zone if a domain is intentionally enabled;
- IAM roles and policies that carry no hourly charge;
- budget and anomaly-monitor configuration.

Everything else must appear in the session teardown inventory.

## References

Pricing and program details must be rechecked before AWS deployment:

- [Amazon EKS pricing](https://aws.amazon.com/eks/pricing/)
- [Elastic Load Balancing pricing](https://aws.amazon.com/elasticloadbalancing/pricing/)
- [NAT Gateway pricing](https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-pricing.html)
- [AWS Budgets](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-create.html)

