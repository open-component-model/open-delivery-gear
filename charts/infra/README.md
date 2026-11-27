# infra

ODG control plane infrastructure as a single Helm chart: a BTP subaccount (adopted), BTP
services (Cloud Logging, Audit Log + Viewer), Gardener provider config and shoots, and
optional per-shoot PostgreSQL. Resources are Crossplane managed objects
(`*.btp.sap.crossplane.io`, `kubernetes.crossplane.io`) reconciled on the control plane.

One-time manual subaccount preparation (provider credential secrets, IAS tenant and
applications, PostgreSQL entitlements) is in [docs/SUBACCOUNT.md](docs/SUBACCOUNT.md).

## Layout

```
infra/
├── Chart.yaml
├── values.yaml            # defaults + required ("") fields, inline docs per key
├── values.example.yaml    # template landscape override (copy, fill in, keep out of git)
├── docs/SUBACCOUNT.md      # one-time manual subaccount preparation
└── templates/
    ├── _helpers.tpl
    ├── btp-subaccount/     # ProviderConfig, Subaccount, Entitlements, ServiceManager, CloudManagement
    ├── btp-services/       # Cloud Logging, Audit Log (+ Viewer), role assignments, PostgreSQL
    ├── gardener/           # Kubernetes ProviderConfig, RBAC, audit policy + credentials Objects
    └── shoots/             # Gardener Shoot Objects (one per shoots[] entry)
```

## Resources

| Resource | Purpose |
|----------|---------|
| BTP Subaccount | Pre-existing, adopted (`deletionPolicy: Orphan`) |
| ServiceManager / CloudManagement | Provisioning BTP services / subscriptions |
| Cloud Logging | Centralized logging (OpenTelemetry ingest) |
| Audit Log (+ Viewer) | Kubernetes API audit logs to BTP; UI + per-user role assignments |
| Gardener ProviderConfig + RBAC | Lets the Crossplane kubernetes provider manage Shoots |
| Shared audit resources | `audit-policy` ConfigMap + `auditlog-credentials` Secret in the garden namespace |
| Gardener Shoot | Kubernetes cluster on OpenStack (cilium) |
| Cloud Logging SAML SSO | Optional (`cloudLogging.saml.enabled`); IAS tenant/app manual |
| Shoot OIDC access | Optional (`shootOidc.enabled`); IAS app + RBAC manual |
| PostgreSQL per shoot | Optional (`postgres.enabled`); per-shoot instance + binding, plus entitlements |

## Values

Override the chart defaults in `values.yaml` (every key is documented inline): copy
`values.example.yaml`, fill it in, and supply it to your release. Notes on the optional
features:

- **IAS features** (`cloudLogging.saml`, `shootOidc`): set `ias.tenantHost` once; the chart
  derives SAML/OIDC URLs and writes parameters only. It creates no IAS objects or secrets
  (SAML OPTION 2). Tenant, applications, and per-shoot RBAC are set up manually, see
  [docs/SUBACCOUNT.md](docs/SUBACCOUNT.md).
- **PostgreSQL** (`postgres.enabled`): renders per-shoot `postgresql-db` ServiceInstance +
  ServiceBinding (connection secret `postgres-<shoot>-credentials`) plus the compute and
  storage entitlements. `createInstances: false` renders entitlements only. Instance params
  (`memory`, `storageGB`, `allow_access` from each shoot's egress IP, etc.) and the
  entitlement model are documented in `values.yaml` and
  [docs/SUBACCOUNT.md](docs/SUBACCOUNT.md#postgresql-entitlements-and-manual-instances).

## Prerequisites

The chart assumes, on the control plane:

- Crossplane with the BTP and kubernetes providers installed and healthy.
- Provider credential secrets in `manual-secrets` (`cis-provider-secret`,
  `sa-provider-secret`, `gardener-kubeconfig`), see [docs/SUBACCOUNT.md](docs/SUBACCOUNT.md).
- For `cloudLogging.saml` / `shootOidc`: the IAS tenant and its applications already set up
  (manual), with their values supplied in the override.

## Render and validate

```bash
# my-values.yaml = filled-in copy of values.example.yaml
helm lint charts/infra -f my-values.yaml
helm template infra charts/infra -f my-values.yaml
helm template infra charts/infra -f my-values.yaml | kubectl apply --dry-run=server -f -
```
