# Local tooling

## Workstation

- Fedora Silverblue 43
- Existing Toolbox container: `admin` based on Fedora Toolbox 43
- Host container engine: Podman

Silverblue should remain clean. AWS, Kubernetes, and infrastructure CLIs will
be installed in a Toolbox rather than layered onto the operating system.

## Inventory captured on 2026-07-17

| Tool | Host | Existing `admin` Toolbox |
|---|---|---|
| Git | Available | Available |
| Python | 3.14.6 | Available |
| Node.js | 24.11.0 | Missing |
| npm | 11.6.1 | Missing |
| Podman | Installed; sandbox could not inspect runtime | Not expected inside Toolbox |
| AWS CLI | Missing | Missing |
| kubectl | Missing | Missing |
| eksctl | Missing | Missing |
| kind | Missing | Missing |
| Helm | Missing | Missing |
| Terraform | Missing | Missing |
| Draw.io CLI | Missing | Missing |

The Podman result above reflects the restricted automation sandbox, not proof
that Podman is broken in the interactive desktop session.

Run the prerequisite check from the project root:

```bash
./scripts/check-tools.sh
```

## Installation approach

The preferred next step is a dedicated project Toolbox, for example
`bedoux-aws`, instead of adding unrelated tools to the existing `admin`
Toolbox. The project Toolbox will contain:

- AWS CLI v2;
- kubectl;
- eksctl;
- kind;
- Helm;
- Terraform;
- Node.js, npm, Python, Git, Make, jq, curl, and unzip.

Tool versions must be pinned after checking current official releases and EKS
compatibility. Installation must not create AWS credentials or contact the AWS
account.

