# Local tooling

## Workstation

- Fedora Silverblue 43 (immutable/atomic host)
- Host container engine: Podman (rootless)
- Toolbox container: `bedoux-aws` (Fedora Toolbox 43) — holds `make` and any other
  dnf-only package this project needs. A pre-existing unrelated `admin` toolbox is left
  untouched.

Silverblue stays clean: nothing is layered onto the OS image with `rpm-ostree`. Two
installation methods are used instead, chosen per tool:

- **Static official binaries** (aws, kubectl, eksctl, kind, helm, terraform) are installed
  directly to `~/.local/bin` on the **host**. This is the standard atomic-Fedora pattern for
  single-binary CLIs — no toolbox, no container-in-container networking, and `kind` gets
  direct access to the host's real Podman.
- **dnf-only packages** (`make`, plus `node`/`npm` as a fallback if the editor-bundled Node
  ever isn't on `PATH`) live in the `bedoux-aws` toolbox.

### The `make` wrapper

Because `make` is toolbox-only but this project's docs describe `make <target>` as a plain
host command, `~/.local/bin/make` is a small wrapper:

```bash
exec toolbox run -c bedoux-aws /usr/bin/make "$@"
```

**It calls `/usr/bin/make` by absolute path, not by name.** The toolbox shares this same
`$HOME` (and therefore `~/.local/bin`) on its `PATH`, so a bare `make` inside the toolbox
would resolve back to this same wrapper and recurse — this was hit once during setup (P1.1)
and exhausted the process/fork limit before the fix. Do not "simplify" this wrapper to
`exec toolbox run -c bedoux-aws make "$@"`.

`podman` is also installed as a package *inside* `bedoux-aws` (dnf, not host-mounted) purely
so `command -v podman` succeeds there too and `make tools-check` reports cleanly regardless
of which shell it's invoked from. **Real Podman/kind/Compose work must run from the host
shell**, not inside the toolbox — nested Podman there is not a functioning container runtime,
only a presence check.

## Pinned versions (installed 2026-07-18)

| Tool | Version | Location | Install method |
|---|---|---|---|
| git | host default | `/usr/bin/git` | Fedora base image |
| make | GNU Make 4.4.1 | toolbox `bedoux-aws` → `/usr/bin/make`, wrapped at host `~/.local/bin/make` | `dnf install make` in toolbox |
| xmllint | host default (libxml2) | `/usr/bin/xmllint` | Fedora base image |
| python3 | 3.14.6 | `/usr/bin/python3` | Fedora base image |
| node / npm | 24.11.0 / 11.6.1 | editor-bundled (see note) | pre-existing |
| podman | 5.8.4 | `/usr/bin/podman` (host) | Fedora base image |
| aws-cli | 2.36.2 | `~/.local/bin/aws` | official installer, `~/.local/aws-cli` |
| kubectl | v1.36.2 (client) | `~/.local/bin/kubectl` | official static binary (`stable.txt` channel) |
| eksctl | 0.229.0 | `~/.local/bin/eksctl` | official GitHub release tarball |
| kind | v0.32.0 | `~/.local/bin/kind` | official static binary |
| helm | v3.21.3 | `~/.local/bin/helm` | official `get-helm-3` install script |
| terraform | v1.15.8 | `~/.local/bin/terraform` | official HashiCorp release zip |
| trivy | 0.72.0 | `~/.local/bin/trivy` | official GitHub release tarball (added P2.5, for image scanning) |
| Calico | v3.32.1 | in-cluster manifest, not a host binary | official manifest (added P10.2, NetworkPolicy enforcement on kind — see below) |
| Metrics Server | v0.9.0 | installed by `scripts/install-metrics-server.sh` | official release manifest, SHA-256 pinned (added P11.1 for HPA metrics; compatible with Kubernetes 1.31+) |

P10.3's supply-chain tools run only on GitHub-hosted runners; they are not workstation
prerequisites. The workflow pins `cosign-installer` v4.1.2 by immutable commit and explicitly
selects cosign v3.0.6; pins `sbom-action` v0.24.0 by immutable commit and explicitly selects Syft
v1.50.0; pins `upload-artifact` v7.0.1 by immutable commit; and uses `registry:2.8.3` only as an
ephemeral PR-job service. SPDX JSON artifacts retain for seven days.

All JavaScript GitHub Actions now use releases whose official manifests declare `node24`:
`checkout` v7.0.1, `setup-python` v7.0.0, `setup-node` v7.0.0,
`setup-terraform` v4.0.1, `setup-helm` v5.0.1, and
`configure-aws-credentials` v6.2.3. Every external action reference is pinned to its immutable
40-character commit SHA. Run `make actions-check` to reject mutable tags before push;
`make docs-check` includes the same check.

`node`/`npm` currently resolve to a Zed-editor-bundled install
(`~/.local/share/zed/node/...`), which is outside this project's control. If that ever
disappears from `PATH`, install `nodejs`/`npm` into the `bedoux-aws` toolbox the same way as
`make`.

Run the prerequisite check from the project root (works transparently from a plain host
shell via the `make` wrapper above):

```bash
make tools-check
```

## Rootless kind + cgroup delegation (fixed 2026-07-19)

`kind create cluster` against the host's **rootless** Podman originally failed:

```text
ERROR: failed to create cluster: running kind with rootless provider requires setting
systemd property "Delegate=yes", see https://kind.sigs.k8s.io/docs/user/rootless/
```

**Fix (host-level, requires root, done once):**

```bash
sudo mkdir -p /etc/systemd/system/user@.service.d
printf '[Service]\nDelegate=yes\n' | sudo tee /etc/systemd/system/user@.service.d/delegate.conf
sudo systemctl daemon-reload
```

Then log out/in or reboot so the new `user@<uid>.service` picks up the drop-in. Verify with
the **system** manager (not `--user`, which queries the wrong bus):

```bash
systemctl show user@$(id -u).service | grep -i delegate
# Delegate=yes
# DelegateControllers=cpu cpuset io memory pids
```

**Second gotcha found during verification:** the delegation is real, but any given shell's
*own* cgroup only inherits the delegated controllers if it lives under `app.slice` (or another
slice systemd fully delegates). A shell nested under `session.slice/org.gnome.Shell@wayland.service`
(as this agent's shell was) only gets `memory pids` auto-enabled there, not `cpu`/`cpuset`/`io`
— so `kind create cluster` still failed with the same error even after the drop-in was applied
correctly. Confirm the failing shell's own path:

```bash
cat /proc/self/cgroup
cat /sys/fs/cgroup/<that path>/cgroup.controllers   # must include cpuset cpu io memory pids
```

If it's short on controllers, run kind (or any rootless-Podman workload) inside an explicit
delegated scope under `app.slice` instead of relying on the ambient shell:

```bash
systemd-run --user --scope --slice=app.slice -p Delegate=yes kind create cluster --name <name>
```

Verified end-to-end 2026-07-19: cluster created, `kubectl get nodes` showed a real node,
`kind delete cluster` removed it cleanly, `kind get clusters` confirmed none left. P3.1 can
create its real cluster directly; no gap remains.

## Loading locally-built images into kind (added P3.1)

`kind load docker-image <image>` fails on this host's rootless-Podman provider:

```text
ERROR: image: "localhost/bedoux-api:p3" not present locally
```

— even when the tag matches `podman images` exactly. Use `podman save` + the
`image-archive` subcommand instead:

```bash
podman save -o /tmp/<name>.tar localhost/<image>:<tag>
kind load image-archive /tmp/<name>.tar --name <cluster>
rm /tmp/<name>.tar
```

Confirm it landed with `podman exec <cluster>-control-plane crictl images | grep <name>`
(faster than waiting for a pod to fail scheduling). Remember `kind load` also needs the
`app.slice` delegated-scope wrapper from the section above, same as `kind create cluster`.

### Kubernetes 1.34 / containerd 2.1 rootless import finding

P11.4 found two additional limits on the pinned kind v0.32.0 / node v1.34.0 combination. First,
the workstation's original `fs.inotify.max_user_instances=128` can be exhausted by existing
rootless containers, causing containerd's CRI plugin to fail while creating its CNI watcher. Any
owner-approved transient increase must be restored after the drill; do not persist a sysctl change
silently.

Second, with `KIND_EXPERIMENTAL_CONTAINERD_SNAPSHOTTER=fuse-overlayfs`, kind's archive loader
invokes containerd 2.1.3 with `--all-platforms`, which failed locally with `no unpack platforms
defined`. The validated local-only fallback is to copy the archive into each required node and
specify the host platform and local importer explicitly:

```bash
podman cp /tmp/<image>.tar <node>:/tmp/<image>.tar
podman exec <node> ctr --namespace=k8s.io images import \
  --platform linux/amd64 --local --digests --snapshotter=fuse-overlayfs \
  /tmp/<image>.tar
```

Delete the in-node and host archives during teardown. This workaround changes only the temporary
node image store; it does not justify floating kind, Kubernetes, or application image versions.

P13.2 found one retained-node restart wrinkle: `containerd-fuse-overlayfs.service` can remain
inactive after the node container restarts even though `ctr plugins ls` reports the configured
proxy snapshotter as `ok`. The first import then registers the image manifest but fails to unpack
while dialing the absent `/run/containerd-fuse-overlayfs.sock`. Before retrying the same bounded
import, verify and recover the existing node-local service explicitly:

```bash
podman exec <node> systemctl start containerd-fuse-overlayfs.service
podman exec <node> systemctl is-active containerd-fuse-overlayfs.service
podman exec <node> test -S /run/containerd-fuse-overlayfs.sock
```

Do not change containerd configuration or switch snapshotters. Re-import the preserved archive,
verify the exact tag through `crictl images`, and remove any failed-attempt alias plus all
drill-specific tags and archives during cleanup.

## NetworkPolicy-enforcing kind cluster (added P10.2)

kind's default CNI, **kindnet, does not enforce `NetworkPolicy` at all** — the objects
apply cleanly to the API server and every command reports success, but traffic is never
actually blocked. Proving `charts/bedoux`'s `networkPolicy.enabled` templates for real
requires disabling the default CNI and installing one that enforces policy (Calico here,
pinned to whatever `curl -s https://api.github.com/repos/projectcalico/calico/releases/latest`
reports at setup time — v3.32.1 as of P10.2).

`k8s/kind-config.yaml` sets `networking.disableDefaultCNI: true` and a matching
`podSubnet: "192.168.0.0/16"` (Calico's own default, so its manifest applies unmodified).
After `kind create cluster`, before anything else:

```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.1/manifests/calico.yaml
kubectl wait --for=condition=Ready node/<cluster>-control-plane --timeout=180s
kubectl wait --for=condition=Ready pod -l k8s-app=calico-node -n kube-system --timeout=180s
```

Then install ingress-nginx and load images as usual. **Two real environmental findings
from doing this on this host, with bounded mitigations:**

1. **ingress-nginx's hostPort mapping breaks** (`CNI-HOSTPORT-SETMARK` iptables chain
   creation fails with `can't initialize iptables table 'nat'`) once the default CNI is
   disabled. Cause: the kind node image's `iptables` alternative defaults to
   `iptables-legacy`, which needs the classic `iptable_nat` kernel module — not loaded on
   this host (only the nftables-based `nft_nat` is). Fix, once per cluster: switch the
   node to the nft-backed binary, which uses the module that's already loaded, then
   delete the stuck pod so it reschedules:
   ```bash
   podman exec <cluster>-control-plane update-alternatives --set iptables /usr/sbin/iptables-nft
   kubectl delete pod -n ingress-nginx -l app.kubernetes.io/component=controller
   ```
2. **ingress-nginx then crash-loops with `too many open files`** creating its file
   watcher — not a container resource limit, but the *host's* `fs.inotify.max_user_instances`
   (default 128 on this host) nearly exhausted by kubelet/containerd/Calico plus several
   long-running MCP sidecar containers sharing the same user. Check usage with
   `cat /proc/sys/fs/inotify/max_user_instances` against a count of open `inotify` fds
   across `/proc/*/fd`. Before changing it, record the current value and obtain owner approval.
   For the exact bounded drill only, the validated transient mitigation is
   `sudo sysctl -w fs.inotify.max_user_instances=1024`; restore the recorded original value
   immediately after teardown (`128` was the original value on this host). Do not persist this
   sysctl change.

Both were host-state issues specific to running many long-lived containers on this
workstation, not a project or Calico bug — recorded here so a future session recognizes
them immediately instead of re-diagnosing from scratch.

## Real-browser verification via Playwright MCP (added 2026-07-19)

This host has no other browser-automation tool, and the owner requires that any
browser driven here be **actual Google Chrome** (installed as Flatpak `com.google.Chrome`
— there is no native `google-chrome` binary on this Fedora Silverblue host, so
Playwright's `--browser chrome` channel auto-detect won't find it). The working setup
instead attaches Playwright MCP to a real Chrome via CDP:

```bash
# 1. Launch real Chrome with a debug port, throwaway profile (never the owner's real one)
flatpak run com.google.Chrome --remote-debugging-port=9222 \
  --user-data-dir=/tmp/chrome-mcp-profile --no-first-run about:blank &
disown

# 2. Confirm the CDP endpoint is up
curl -s http://127.0.0.1:9222/json/version

# 3. Playwright MCP is registered (once) to attach, not launch its own browser:
claude mcp add playwright -s local -- npx -y @playwright/mcp@latest --cdp-endpoint http://127.0.0.1:9222
```

**Known gotcha:** the Chrome process from step 1 is a plain background job. It does not
survive an agent-session restart or host reboot — relaunch it first, or the
`mcp__playwright__*` tools will fail to connect. Newly-added/changed MCP servers also
don't appear in an already-running agent session's tool list — the session itself needs
restarting once after `claude mcp add`/`remove`.

## Scanning container images (added P2.5)

No podman socket is active by default on this host, so `trivy image <name>` (which looks for
a running daemon) fails. Export the image and scan the tarball instead:

```bash
podman save -o /tmp/image.tar <image>:<tag>
trivy image --severity HIGH,CRITICAL --input /tmp/image.tar
rm /tmp/image.tar   # don't leave scan tarballs lying around
```

## Installation approach (completed in P1.1)

Tool versions above were pinned by checking current official releases at install time
(2026-07-18). No AWS credentials were created and no AWS account was contacted — `aws`,
`kubectl`, and `eksctl` were installed and version-checked only; `eksctl create cluster` was
not run.

## AWS CLI identity: always `--profile bedoux-admin` (added P4.1)

The AWS account's `root` user was used only once, briefly, to bootstrap (via `aws login`
browser SSO — a temporary session, never long-lived root access keys) — enough to enable
root MFA and create a non-root IAM user. All routine work uses a **named profile**, never
the default/root session:

```bash
aws configure --profile bedoux-admin   # one-time, enters an access key ID/secret locally
aws sts get-caller-identity --profile bedoux-admin   # must show user/bedoux-admin, never :root
```

`bedoux-admin` is an IAM user (not IAM Identity Center — simpler for a solo learning
account) in the `bedoux-admins` group, which has two policies attached:

- **`PowerUserAccess`** (AWS managed) — covers every service this project touches
  (EC2/VPC, EKS, ECR, ELB, CloudFormation, S3, CloudWatch, Budgets) but **excludes
  IAM/Organizations management**, so this identity cannot grant itself more power.
- **A small custom policy** (`bedoux-iam-scoped`, owner-applied v6) granting IAM role/policy/OIDC-provider
  actions **only on resources named `bedoux-*`** — the minimum needed for `eksctl` and
  IRSA (EKS pods assuming IAM roles) to create the roles they need, without general IAM
  management. Every IAM role/policy this project creates must keep the `bedoux-` prefix
  for this scoping to keep working.

Every AWS command in this project — CLI, `eksctl`, Terraform, the `/aws-*` slash
commands — should run with `--profile bedoux-admin` (or `AWS_PROFILE=bedoux-admin`
exported for the session) unless a step explicitly says otherwise. Root is reserved for
account-level console actions only (MFA, billing), never CLI work.
