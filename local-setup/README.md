# Deploying the Open Delivery Gear Locally

This guide will help you deploy a custom Open Delivery Gear (ODG) on your local
machine using [KinD](https://kind.sigs.k8s.io/). If you encounter any problems,
please feel free to [open an issue](https://github.com/open-component-model/open-delivery-gear/issues/new?template=bug.md)
so that we can improve this process or documentation.

## Prerequisites
To get started, you first of all need to install the required toolchain:
- [Kubectl](https://kubernetes.io/docs/tasks/tools)
- [KinD](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- [Helm](https://helm.sh/docs/intro/install)
- [OCM CLI](https://github.com/open-component-model/open-component-model#ocm-cli)

## Configuration
To customise ODG according to your needs, you have to adjust the [values file](https://github.com/open-component-model/open-delivery-gear/blob/main/local-setup/kind/values.yaml).
There are already reasonable defaults available for most entries, however,
following entries must still be provided:
- OCI registry credentials to access desired component descriptors and
resources via `secrets.oci-registry` (in case they are not publicly available)
- GitHub credentials via `.secrets.github` or `.secrets.github-app` (both to
allow authentication within ODG itself as well to access necessary
repositories)
- GitHub App credentials to allow OAuth  
    (1) Go to your GitHub organisation's settings  
    (2) Developer settings -> GitHub Apps -> New GitHub App  
    (3) Fill in the form ("Callback URL" -> `http://localhost:3000`, "Request
    user authorisation (OAuth) during installation" -> `True`, other checkboxes
    -> `False`)  
    (4) Fill in `client_id`, `client_secret` and desired `role_bindings` via
    `secrets.oauth-cfg`  

## Start-Up
To create a local Kubernetes cluster and deploy ODG, you have to run
`make kind-up`. If you want to deploy a specific version of ODG, you have to
set the environment variable `ODG_VERSION`. Otherwise, the OCM CLI is used to
retrieve the greatest version. Upon execution, this command will create
`<REPO_ROOT>/local-setup/kind/kubeconfig` which can be used to interact with
the ODG cluster. Also, it will forward the delivery-service to
`http://localhost:5000` and the delivery-dashboard to `http://localhost:3000`.

> [!NOTE]  
> Currently, the listing of available versions via OCM CLI is not working for
> the OCM component descriptor of ODG. Therefore, an explicit version MUST be
> set via the `ODG_VERSION` environment variable.

## Configuration Update
To update the ODG deployment in case your local configuration has changed, just
run the `make kind-update` command. This will upgrade the existing Helm charts
and re-apply your configuration settings without the need to re-create your
KinD cluster.

## Termination
If you wish to stop ODG and delete the KinD cluster, you have to run
`make kind-down`. However, this will _not_ delete the database storage since it
is permanently stored on the host machine. To also clear the database storage,
you have to delete the `/var/delivery-db` directory.

## External PostgreSQL

By default, `make kind-up` deploys a bundled PostgreSQL instance inside the
KinD cluster. If you want to use a managed or external PostgreSQL database
instead, add a `hostname` to the `delivery-db` secret in
`local-setup/kind/secrets-local.yaml`:

```yaml
secrets:
  delivery-db:
    local:
      username: postgres
      password: <password>
      hostname: <host>   # e.g. host.docker.internal
      port: 5432         # optional, defaults to 5432
      database: ""       # optional
```

When `hostname` is set, `make kind-up` and `make kind-update` will
automatically skip the bundled `delivery-db` Helm chart. The bootstrapping
chart picks up `hostname` from the secret values and uses it directly in the
connection URL.

## Extensions
ODG extensions can be dynamically added to your installation. Therefore, the
configuration of the extensions must be done via `extensions_cfg` in the
[values file](https://github.com/open-component-model/open-delivery-gear/blob/main/local-setup/kind/values.yaml).

## Observability

To add metrics and dashboards on top of your local ODG, run:

    make kind-observability-on

You need a checkout of the [odg-observability](https://github.com/open-component-model/odg-observability)
repository. By default the script looks for it next to this repository
(`../odg-observability`). To use a different location, set the environment
variable `ODG_OBSERVABILITY`:

    ODG_OBSERVABILITY=/path/to/odg-observability make kind-observability-on

Everything runs inside the KinD cluster — nothing is started on your Mac.

### What gets deployed from where

| Component | Comes from |
|---|---|
| OpenSearch + OpenSearch Dashboards | raw manifests in this repo: `local-setup/kind/telemetry/` |
| Network policies for the above | same folder (`networkpolicies.yaml`) |
| Prometheus operator, Prometheus, kube-state-metrics, Perses | `odg-observability/charts/prometheus-operator` |
| OTel collector, metrics-operator | `odg-observability/charts/telemetry` |

The OTel collector ships the logs of all pods in the `odg` namespace to the
in-cluster OpenSearch (delivery-dashboard and delivery-db are excluded in the
chart — too noisy). Prometheus scrapes the collector and kube-state-metrics.
Perses serves the dashboards, backed by Prometheus.

### Endpoints on localhost

After `make kind-observability-on` finishes, these port-forwards are running:

| URL | What |
|---|---|
| http://localhost:8080 | Perses (Dashboards → odg) |
| http://localhost:9090 | Prometheus UI |
| http://localhost:5601 | OpenSearch Dashboards (Discover → `logs-otel-v1`) |
| grpc://localhost:4317 | OTLP endpoint — push traces/metrics from apps on your Mac |

The port-forwards restart themselves on drops (pod restart, laptop sleep).
They stop on their own when the cluster is gone — after 3 failed connection
checks in a row the loop exits, so nothing keeps running after
`make kind-down`, a reboot, or a deleted kubeconfig. To bring them back after
a reboot, rerun `make kind-observability-on` (fast when everything is warm).
Logs: `/tmp/pf-*.log`.

### Removal

There is no separate off-switch. The stack lives entirely inside the KinD
cluster, so `make kind-down` removes everything. OpenSearch data itself sits
on a PVC inside the cluster and is removed together with it.
