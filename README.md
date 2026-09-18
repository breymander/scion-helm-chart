# Scion Helm Chart

A Helm chart for running [Scion](https://github.com/GoogleCloudPlatform/scion) —
Google's open-source agent-orchestration platform, a "hypervisor for agents" —
on **self-managed Kubernetes**.

Scion runs deep-agent harnesses (Claude Code, Gemini CLI, Codex, OpenCode, …)
as isolated pods, each with its own container, workspace and credentials. This
chart deploys the **hub**: the control plane, its in-process runtime broker, and
the web UI.

> Not an official Google product. See [NOTICE](NOTICE).

## Why this chart exists

Upstream ships a chart at `deploy/helm/scion-hub`, and its own `Chart.yaml`
describes it as *"for Google Kubernetes Engine."* That is accurate. It is built
around Cloud SQL, Cloud Storage, Google Secret Manager, Workload Identity and
IAP. On a cluster that has none of those, most of the chart is inert and some of
it is actively wrong.

This is a rewrite rather than a fork, because the parts worth keeping are
smaller than the parts that had to go.

### What it drops

| Upstream | Why |
| --- | --- |
| `cloudsql.*` — Auth Proxy sidecar, native-sidecar guard, IAM DB auth | Nothing to connect to |
| `storage.provider: gcs` | Blobs live on the PVC |
| `secrets.backend: gcpsm` | Credentials come from Kubernetes Secrets |
| `serviceAccount.gcpServiceAccount`, `iam.gke.io/*` | No Workload Identity |
| `auth.mode: proxy` via IAP, `transport.iap` | Header-based proxy auth is kept; the IAP coupling is not |
| `secretproviderclasses` RBAC | That is the GKE Secret Store CSI driver |
| `acknowledgeHAUnlanded` + HA preflight | Upstream documents its own HA path as unlanded; this chart is single-replica by construction |

### Three upstream behaviours it corrects

Each was verified against the published artifacts, not inferred from docs:

1. **`gke: true` was hardcoded.** Upstream's settings render emits
   `runtimes.kubernetes.gke = true` unconditionally, with no value to disable
   it. Off GKE, that sends the hub to Application Default Credentials and the
   GKE Secret Store CSI driver. This chart never emits the key.

2. **Container args omitted the binary name.** The image entrypoint is
   `["sciontool", "init", "--"]`, so args are the command to exec. Upstream
   passes `["server", "start", …]` — a binary literally named `server`. This
   chart passes `["scion", "server", "start", …]`.

3. **No `fsGroup`, on a volume that must be written as uid 1000.** A freshly
   provisioned PVC mounts `root:root` `0755`; the hub runs as uid 1000 and must
   create `hub.db` inside it. Upstream only gets away with this because its
   volume is an `emptyDir` — and an `emptyDir` is precisely what makes the hub
   lose all state on restart, since `hub.db` lives there.

## Requirements

- Kubernetes 1.19+, Helm 3+
- An Ingress controller and, for TLS, cert-manager (or bring your own cert)
- A StorageClass for the hub's state
- A hub image **with web assets embedded** — see below
- OAuth credentials (GitHub or Google), unless fronting the hub with an auth proxy

## The image caveat (read this first)

`image.repository` has no default, and the obvious candidate does not work for
the web UI.

`ghcr.io/homebrew-scion/scion-hub` derives from `scion-base`, which builds the
binary with `-tags no_embed_web`. That binary logs:

```
This binary was built without web assets. The web UI will not be available.
```

…and `--enable-web` serves nothing. The images are genuine multi-arch
(`linux/amd64` + `linux/arm64`) and the hub's JSON API works fine — but there is
no dashboard.

Two ways forward:

**Build an image with assets embedded** (`make web && make build`, i.e. no
`no_embed_web` tag), then point `image.repository` at it.

**Or mount the client** — build `web/dist/client` once, put it on a volume, and
set `hub.webAssetsDir` plus `hub.extraVolumes` / `hub.extraVolumeMounts`.

## Install

```bash
helm repo add scion https://breymander.github.io/scion-helm-chart
helm repo update

helm install scion scion/scion \
  --namespace scion --create-namespace \
  -f my-values.yaml
```

A minimal `my-values.yaml`:

```yaml
image:
  repository: ghcr.io/you/scion-hub
  tag: v0.2.20

hub:
  hubId: my-hub
  baseUrl: https://scion.example.com   # must be https
  adminEmails:
    - you@example.com                  # the email your provider returns

auth:
  oauth:
    github:
      clientId: "..."
      clientSecret: "..."

agents:
  credentials:
    anthropicApiKey: "sk-ant-..."

persistence:
  storageClass: longhorn

ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/issuer: letsencrypt-prod
    # Agent output streams for as long as an agent runs; nginx's 60s default
    # would cut the session view off mid-task.
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
```

Register the callback URL your provider needs — the chart prints it on install:

```
https://scion.example.com/auth/callback/github
```

## Access control

**The upstream default is open.** `checkUserAuthorized` ends in
`default: // "open" or empty -> return true`, and the upstream chart sets no
mode. With a GitHub OAuth app, "anyone the provider authenticates" means any
GitHub user — who can then have your hub run containers with your model
credentials.

This chart defaults `auth.userAccessMode` to `invite_only` and refuses to render
`open` unless you also set `auth.acknowledgeOpenAccess: true`.

Valid values are `invite_only`, `domain_restricted` and `open` — the three the
code switches on. Upstream's `settings.yaml.example` documents
`"open"/"domain"/"allowlist"`; **`allowlist` is not implemented** and falls
through to open. The chart rejects it rather than letting it mean its opposite.

`hub.adminEmails` bypasses every check, so it is also the break-glass list. On a
fresh install with `invite_only` and no admin emails, nobody could ever log in —
invitations can only be sent from inside — so the chart fails the render instead.

## Persistence

The hub's state root is `<hub.home>/.scion`, and that is where SQLite puts
`hub.db` and where the local blob store lives. With `persistence.enabled: false`
it is an `emptyDir`, and every restart, eviction and upgrade resets the hub.

The claim is annotated `helm.sh/resource-policy: keep`, so `helm uninstall` does
not delete your database. Remove it by hand when you actually mean to.

Single replica with `strategy: Recreate` is deliberate and not configurable: one
SQLite file and one local blob store on a ReadWriteOnce claim is a single-writer
design.

## Agent pods

By default agents run in the release namespace. Set `agents.namespace` to give
them their own RBAC boundary; the chart grants the hub rights there either way —
create/delete pods, `pods/exec` (workspace sync and tmux attach), `pods/log`,
and the Secrets holding each agent's credentials.

`agents.listAllNamespaces: true` additionally renders a ClusterRole. It is the
only permission in this chart that reaches outside its own namespaces.

Harness images come from `agents.imageRegistry`, default
`ghcr.io/homebrew-scion` (`scion-claude`, `scion-gemini`, `scion-codex`,
`scion-opencode`, `scion-copilot`, …), all published multi-arch including arm64.

## Values

See [`values.yaml`](values.yaml) — every key is commented, and
`values.schema.json` rejects unknown keys so typos fail at install rather than
silently doing nothing.

## License

Apache 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
