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

`node`/`npm` currently resolve to a Zed-editor-bundled install
(`~/.local/share/zed/node/...`), which is outside this project's control. If that ever
disappears from `PATH`, install `nodejs`/`npm` into the `bedoux-aws` toolbox the same way as
`make`.

Run the prerequisite check from the project root (works transparently from a plain host
shell via the `make` wrapper above):

```bash
make tools-check
```

## Known gap for P3 (local Kubernetes)

`kind create cluster` against the host's **rootless** Podman fails today:

```text
ERROR: failed to create cluster: running kind with rootless provider requires setting
systemd property "Delegate=yes", see https://kind.sigs.k8s.io/docs/user/rootless/
```

This needs a `systemd --user` cgroup delegation drop-in before P3 can create a real cluster.
Not fixed during P1 — toolchain presence is P1's scope; a working cluster is P3's. Address it
at the start of P3.1 and record the fix + evidence there.

## Installation approach (completed in P1.1)

Tool versions above were pinned by checking current official releases at install time
(2026-07-18). No AWS credentials were created and no AWS account was contacted — `aws`,
`kubectl`, and `eksctl` were installed and version-checked only; `eksctl create cluster` was
not run.
