# P11.4 bounded EKS node-loss drill

This runbook prepares T-1103: drain the stateless node in one AZ while a public catalog load
test is running, prove zero failed requests and API/web recovery in the surviving AZ, restore
normal cross-AZ placement, and tear the whole session down the same day. It does not claim
PostgreSQL high availability.

ADR 0017 is Proposed. The owner must accept its two tradeoffs before apply: two one-node,
AZ-pinned managed node groups and `ScheduleAnyway` topology spread in the AWS HA overlay.

## Session boundary

1. Complete every **Before the session** item in `docs/runbooks/aws-session.md` with the
   non-root `bedoux-admin` profile and pinned `ca-central-1` region.
2. Record the deadline and independent alarm in `docs/PROGRESS.md`. Reserve at least 45 minutes
   for teardown; the alarm ends the drill even if evidence is incomplete.
3. Confirm current billing remains under the USD 16 stop threshold and inventory is clean.
4. Initialize the persistent backend, import only the persistent allowlist, and save a plan
   using a private copy of `infra/terraform/terraform.tfvars.p11-ha.example`.
5. Refuse the plan unless it has no NAT Gateway, no RDS/S3/Secrets/observability resources, no
   persistent-resource deletes, exactly two one-node Spot `t3.medium` node groups, and the
   already-reviewed EKS/add-on/VPC resources. Record the current regional cost estimate.

No command below opens the AWS session by itself. Do not apply until the owner explicitly
accepts ADR 0017 and the reviewed plan inside the recorded session boundary.

## Healthy baseline

1. Apply only the reviewed plan. Record cluster/node-group creation timestamps.
2. Install the pinned Metrics Server and AWS Load Balancer Controller versions already recorded
   by P11.3, create `gp3`, and deploy the immutable API/web digests with both
   `values-aws.yaml` and `values-aws-ha.yaml`.
3. Use an explicit kubeconfig/context; the workstation default may still reference a deleted
   EKS endpoint. Wait for the ALB health endpoint and catalog endpoint to return HTTP 200.
4. Run the read-only guard:

   ```text
   scripts/p11-node-loss-drill.sh inspect --context <explicit-eks-context>
   ```

   It must report exactly two Ready nodes in two `ca-central-1` AZs, at least two available API
   and web replicas, one permitted disruption in each PDB, and a safe fault candidate that does
   not host PostgreSQL. Stop if any condition differs.
5. Capture sanitized `kubectl get nodes -L topology.kubernetes.io/zone` and
   `kubectl -n bedoux get pods -o wide` output. Confirm API and web each occupy both AZs.

## Load and single fault

1. Preview the mutation with the exact candidate from `inspect`:

   ```text
   scripts/p11-node-loss-drill.sh drain \
     --context <explicit-eks-context> \
     --node <safe-fault-node>
   ```

2. Start pinned k6 `0.52.0` in a second terminal. The defaults are 20 VUs for five minutes;
   the drill must not raise them without a new cost/cap review:

   ```text
   podman run --rm --network host --security-opt label=disable \
     -e BASE_URL=http://<temporary-alb-dns> \
     -v "$PWD/scripts/p11-node-loss-load.js:/drill.js:ro" \
     docker.io/grafana/k6:0.52.0 run /drill.js
   ```

3. After at least 60 seconds of clean traffic, execute the one declared fault:

   ```text
   scripts/p11-node-loss-drill.sh drain \
     --context <explicit-eks-context> \
     --node <safe-fault-node> \
     --execute
   ```

   Do not terminate an EC2 instance, scale a node group, drain the PostgreSQL node, or stack a
   second fault. Diagnose only from `kubectl`, Helm/application output, and approved read-only
   AWS output.
4. The drain must respect both PDBs, API/web must each regain at least two Running replicas on
   the surviving node, and k6 must continue until its fixed duration ends.
5. T-1103 passes only when k6 reports 0% failed requests, 100% successful checks, and p95 below
   two seconds. Record request count, average, p95, p99, pod/node placement, and the drain timing.
   Any failed request means the test did not pass; record it truthfully and recover.

## Recovery and teardown

1. Restore the fault node and normal spread:

   ```text
   scripts/p11-node-loss-drill.sh recover \
     --context <explicit-eks-context> \
     --node <safe-fault-node> \
     --execute
   ```

   The command uncordons the node, uses each Deployment's rolling-update controls to restart
   API/web, and refuses success unless each application returns to two-AZ placement.
2. Re-run the same ALB health/catalog checks used for the baseline. Delete drill-only files or
   pods if any were created.
3. Delete Ingress first and wait for ALB deletion. Uninstall the app/controller and temporary
   Kubernetes prerequisites, then use `scripts/terraform-session-destroy.sh` in its guarded
   `prepare`, `plan`, and explicit `apply` sequence.
4. Complete every inventory check in `docs/runbooks/aws-session.md`: EKS/node groups, ALB/target
   groups, VPC/IGW/subnets, NAT/EIP, instances, volumes/snapshots, RDS, CloudFormation, temporary
   OIDC provider, and Terraform state. Only the documented persistent allowlist may remain.
5. Record T-1103 results, all created/destroyed resources, estimated cost, teardown timestamps,
   and the clean T-1104 sweep in `docs/PROGRESS.md`. P11.4 stays incomplete if recovery or the
   final sweep is not clean.
