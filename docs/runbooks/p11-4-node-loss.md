# P11.4 bounded EKS node-loss drill

This runbook prepares T-1103: drain the stateless node in one AZ while a public catalog load
test is running, prove zero failed requests and API/web recovery in the surviving AZ, restore
normal cross-AZ placement, and tear the whole session down the same day. It does not claim
PostgreSQL high availability.

ADR 0017 is Accepted from a technical-design standpoint: two one-node, AZ-pinned managed node
groups and `ScheduleAnyway` topology spread in the AWS HA overlay. That acceptance permits the
alarmed session and plan review; it does not authorize apply.

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

No command below opens the AWS session by itself. After the saved plan passes every check above,
present that exact plan to the owner. Do not apply until the owner explicitly authorizes it
inside the recorded session boundary.

## Healthy baseline

1. Apply only the reviewed plan. Record cluster/node-group creation timestamps.
2. Install the pinned Metrics Server and AWS Load Balancer Controller versions already recorded
   by P11.3 and create `gp3`. Apply `k8s/00-namespace.yaml`, then label the namespace before any
   application pod is created:

   ```text
   kubectl --context <explicit-eks-context> label namespace bedoux \
     elbv2.k8s.aws/pod-readiness-gate-inject=enabled --overwrite
   ```

3. Bootstrap the Helm release with the reviewed immutable digests, both `values-aws.yaml` and
   `values-aws-ha.yaml`, zero API/web replicas, and both HPAs disabled. This creates the Services
   and Ingress before application pods, as required for deterministic AWS target-health readiness
   gate injection:

   ```text
   # Add these four overrides to the normal immutable-digest helm upgrade --install command.
   --set api.replicas=0 \
   --set web.replicas=0 \
   --set api.autoscaling.enabled=false \
   --set web.autoscaling.enabled=false
   ```

   Wait until the controller creates exactly one `TargetGroupBinding` for the `web` Service.
   Then repeat the same Helm upgrade without those four bootstrap overrides. Refuse to continue
   unless every Running web pod has a `target-health.elbv2.k8s.aws/...` readiness gate and reaches
   `Ready`. PostgreSQL and API are not direct ALB targets and do not receive that gate.
4. Use an explicit kubeconfig/context; the workstation default may still reference a deleted
   EKS endpoint. Wait for the ALB health endpoint and catalog endpoint to return HTTP 200.
5. Run the read-only guard:

   ```text
   scripts/p11-node-loss-drill.sh inspect --context <explicit-eks-context>
   ```

   It must report exactly two Ready nodes in two `ca-central-1` AZs, exactly one Running
   PostgreSQL pod, at least two available API and web replicas, one permitted disruption in each
   PDB, the 30-second ALB deregistration / 45-second preStop / 60-second grace contract, an AWS
   target-health readiness gate on every Running web pod, and a safe fault candidate that does
   not host PostgreSQL. Stop if any condition differs.
6. Capture sanitized `kubectl get nodes -L topology.kubernetes.io/zone` and
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
   The workload emits one timestamped JSON diagnostic for each failed catalog request; preserve
   those lines if any occur. Any failed request means the test did not pass; record it truthfully
   and recover.

## Recovery and teardown

1. Restore the fault node and normal spread:

   ```text
   scripts/p11-node-loss-drill.sh recover \
     --context <explicit-eks-context> \
     --node <safe-fault-node> \
     --execute
   ```

   The command uncordons the node and uses each Deployment's rolling-update controls to restart
   API/web. It waits until terminating pods have disappeared before evaluating placement, so a
   pod in its preStop hold cannot create a false two-AZ result. If stable Ready pods still occupy
   only one AZ, it replaces at most one pod per stateless Deployment, waits for that bounded
   rebalance, and refuses success unless each application then occupies both AZs.
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
