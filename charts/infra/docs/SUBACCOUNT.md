# Preparing the subaccount and landscape

Manual, one-time setup a human must complete **before** Flux reconciles the `infra`
chart. The chart adopts a pre-existing BTP subaccount and consumes resources that are
provisioned out-of-band here (IAS tenant, provider credentials, some BTP entitlements). The
chart itself is documented in the [README](../README.md).

Do these in order:

1. [Provider credential secrets](#provider-credential-secrets)
2. [SAP Cloud Identity Services (IAS) tenant](#sap-cloud-identity-services-ias-tenant)
3. [Cloud Logging OpenSearch Dashboards SSO (IAS SAML 2.0)](#cloud-logging-opensearch-dashboards-sso-ias-saml-20)
4. [Shoot cluster access via IAS OIDC](#shoot-cluster-access-via-ias-oidc)
5. [PostgreSQL entitlements and manual instances](#postgresql-entitlements-and-manual-instances)

## Provider credential secrets

Create these in the `manual-secrets` namespace on the control plane. They hold the
credentials the Crossplane providers use and are managed out-of-band (never in git):

| Secret | Key | Purpose |
|--------|-----|---------|
| `cis-provider-secret` | `data` | CIS (Cloud Management Service) service key for the BTP provider |
| `sa-provider-secret` | `credentials` | BTP technical user the provider authenticates as |
| `gardener-kubeconfig` | `kubeconfig` | ServiceAccount kubeconfig for the Gardener project |

### `cis-provider-secret`

A service key of the subaccount's **Cloud Management Service** (`cis`), plan `local`. Its
`data` value is the raw service-key JSON (`uaa`, `endpoints`, `grant_type`,
`sap.cloud.service`), which is how the BTP provider calls the Cloud Management / entitlements
APIs.

1. In the subaccount, entitle **Cloud Management Service** (`cis`), plan `local`, if not
   already present.
2. Create an instance of `cis` / `local`, then a **service key** on it. BTP cockpit:
   Services > Instances and Subscriptions > create the `cis local` instance, then its key.
   CLI: `btp create services/instance --offering-name cis --plan-name local ...` then
   `btp create services/binding ...`.
3. Copy the full service-key JSON and store it under the `data` key (see commands below).

### `sa-provider-secret`

A **BTP technical (platform) user** the provider logs in with. Its `credentials` value is
JSON with `email`, `username`, `password`. Use a dedicated service/technical account (not a
personal login), granted the roles needed to manage the subaccount (subaccount admin /
entitlements). Obtain it from your BTP user administration (or the shared team credential
store) and store the three fields as JSON under the `credentials` key.

### `gardener-kubeconfig`

A kubeconfig for a Gardener **ServiceAccount** in the garden project that owns the shoots,
with permission to manage `Shoot` resources (and read the `audit-policy` /
`auditlog-credentials` objects the chart writes). The chart's Gardener `ProviderConfig`
points the Crossplane kubernetes provider at this kubeconfig.

1. In the Gardener dashboard for your project, create a **ServiceAccount** (Members >
   Service Accounts), or use `gardenctl`/`kubectl` against the garden cluster.
2. Download its kubeconfig. Prefer a short-lived-token kubeconfig over a static one.
3. Store the kubeconfig verbatim under the `kubeconfig` key.

### Creating the secrets

From files holding each credential (keep the files out of git):

```bash
# cis-service-key.json: the full cis/local service-key JSON
kubectl -n manual-secrets create secret generic cis-provider-secret \
  --from-file=data=cis-service-key.json

# sa-credentials.json: {"email":"...","username":"...","password":"..."}
kubectl -n manual-secrets create secret generic sa-provider-secret \
  --from-file=credentials=sa-credentials.json

# gardener.kubeconfig: the Gardener ServiceAccount kubeconfig
kubectl -n manual-secrets create secret generic gardener-kubeconfig \
  --from-file=kubeconfig=gardener.kubeconfig
```

The `--from-file=<key>=<path>` form keeps the exact key names the chart's ProviderConfigs
expect (`data`, `credentials`, `kubeconfig`).

## SAP Cloud Identity Services (IAS) tenant

The IAS tenant is managed manually (not by the chart). Enter the tenant host once under
`ias.tenantHost` (e.g. `example.accounts.ondemand.com`); it is the single source of
truth for the IAS-backed features below, which derive their URLs from it:

- SAML IdP metadata URL = `https://<ias.tenantHost>/saml2/metadata`
- SAML IdP entity ID = `https://<ias.tenantHost>`
- OIDC issuer = `https://<ias.tenantHost>/`

Each feature can override its URL explicitly (`cloudLogging.saml.idp.metadataUrl` /
`.entityId`, `shootOidc.issuerUrl`) if a landscape is unusual, but normally you only set
`ias.tenantHost` plus the per-application identifiers.

Request the tenant once per landscape: in the BTP cockpit or SAP for Me go to Services >
Service Marketplace > Cloud Identity Services > `additional-tenant` plan > Create, as a
**named administrator** (a human request triggers the activation email that makes that user
the tenant's initial administrator). Activate from the email, then put the tenant host in
`ias.tenantHost`.

## Cloud Logging OpenSearch Dashboards SSO (IAS SAML 2.0)

OpenSearch Dashboards can use IAS SAML 2.0 single sign-on. The IAS tenant and the SAML
application are set up **manually**; the chart only writes the resulting `saml` parameters
onto the Cloud Logging instance. This uses SAML **OPTION 2** (no request signing), so **no
secret is involved**: every value is non-secret and lives in the landscape values override.

Manual setup (once per landscape):

1. Create a SAML 2.0 application in the IAS tenant. Note its `Entity ID` (this is
   `cloudLogging.saml.spEntityId`).
2. Configure the application: define a self-asserted `groups` user attribute so group
   membership is emitted (maps to `roles_key: groups`), set Default Name ID Format = Email.
3. Set the Assertion Consumer Service endpoint to
   `https://<dashboards-endpoint>/_opendistro/_security/saml/acs` and the Single Logout
   endpoint (HTTP-Redirect) to `https://<dashboards-endpoint>` (no trailing path). Read
   `<dashboards-endpoint>` from the `cloud-logging-credentials` secret (`dashboards-endpoint`
   key). This step can only be done after the Cloud Logging instance exists.
4. Create the admin group (`cloudLogging.saml.admin_group`, default `cls-admin`) and assign
   the users who should get OpenSearch Dashboards `all_access`.

Chart configuration: set `cloudLogging.saml.enabled: true` and fill in the `saml` block
under `cloudLogging.saml` (`initiated`, `roles_key`, `admin_group`, `spEntityId`). The IdP
URLs come from `ias.tenantHost`. The chart passes the `saml` block to the Cloud Logging
instance parameters. No Secret and no `parameterSecretRefs` are created.

## Shoot cluster access via IAS OIDC

Set `shootOidc.enabled: true` to let users authenticate to the shoots' kube-apiserver with
tokens from the manual IAS tenant, with an IAS group driving Kubernetes group membership.
The chart uses Kubernetes Structured Authentication (k8s >= 1.30): for each shoot it renders
an `AuthenticationConfiguration` ConfigMap into the garden namespace and sets
`spec.kubernetes.kubeAPIServer.structuredAuthentication.configMapName` on the shoot to
reference it. No secret is involved; the kube-apiserver only validates tokens.

Manual IAS setup (once per landscape):

1. In the IAS tenant, create an **OpenID Connect application** for shoot access. Note the
   client id (this is the token `audiences` value). The issuer is `https://<ias.tenantHost>/`
   and must match the token `iss` claim (including trailing slash).
2. Add a self-defined `groups` attribute to the application so group membership is emitted
   in the token, and set the subject/Name ID to email.
3. Create the IAS group (e.g. `Shoot-Admin`) and assign the users who should get access.
4. Users authenticate with an OIDC `kubectl` plugin (e.g. `kubectl oidc-login` /
   `kubelogin`) against the IAS issuer and client id.

Chart configuration: set `shootOidc.enabled: true` and supply `clientID` (and optionally the
claim names/prefixes). The issuer is derived from `ias.tenantHost`. With the defaults, an IAS
user `jane@sap.com` in group `Shoot-Admin` is seen by the shoot apiserver as username
`ias:jane@sap.com` in group `ias:Shoot-Admin`.

Manual RBAC (once per shoot): the OIDC config only authenticates; it grants no permissions.
Bind the prefixed group to a role in each shoot cluster, for example:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ias-shoot-admins
subjects:
  - kind: Group
    name: "ias:Shoot-Admin"      # groupsPrefix + IAS group name
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin           # or a narrower role
  apiGroup: rbac.authorization.k8s.io
```

Apply it with a shoot `adminkubeconfig` (see Gardener docs). Changing the ConfigMap later is
picked up on the next shoot reconciliation, which is not automatically triggered.

## PostgreSQL entitlements and manual instances

The chart can provision a database per shoot (`postgres.enabled: true`, see the README). The
BTP-side entitlements and any manually created instances are prepared here.

### Entitlements (two SKUs)

PostgreSQL on SAP BTP (hyperscaler option, SCI regions) requires **two** entitlements per the
SAP sizing table, not one:

- the **compute** SKU, the chosen plan (`standard` or `premium`)
- a separate **storage** SKU (`storage`, or `storage_ha` for multi-AZ)

Both SKUs are counted **per instance**. Compute units scale with RAM: for `standard`, each
instance consumes `memory / 2` compute units (2 GB RAM -> 1, 4 GB RAM -> 2). The **storage**
SKU is counted in **5 GB blocks**: each instance consumes `ceil(storageGB / 5)` storage units
(5 GB -> 1, 20 GB -> 4). Multi-AZ doubles the compute SKU and switches the storage SKU to
`storage_ha`.

Example: two single-AZ `standard` instances at 2 GB RAM and 5 GB disk need `standard: 2` and
`storage: 2`. At 20 GB disk the same two instances need `storage: 8`.

The chart's `postgres.yaml` renders both `Entitlement` objects with these amounts derived
from the selected shoots, `postgres.memory`, `postgres.storageGB`, `postgres.plan`,
`postgres.multiAz`, and `postgres.entitlementMultiplier`. The **global account** must hold
enough quota of each SKU to assign to the subaccount, otherwise the
`Entitlement` fails to sync with a quota error (`Code 30009`). Request global-account quota
for both the compute and storage SKUs before enabling postgres.

### Manually created instances (access control)

When creating a PostgreSQL instance by hand (cockpit or CF), two instance parameters control
reachability:

- `public_access` (boolean, default `true`): whether the instance has a public endpoint.
- `allow_access` (string): comma-separated source IPs and CF landscape domains allowed to
  connect. **Empty blocks all public access.** The broker rejects `allow_access` unless
  `public_access: true` is also set (`Must set public_access to true if allow_access is
  provided`).

Gardener shoots are **not** Cloud Foundry, so the default CF-landscape-domain allowance does
not cover them. You must list each shoot's **egress IP** (the source IP the database
observes) in `allow_access`, together with `public_access: true`.

Read each shoot's egress CIDR from its `Shoot` status (Gardener surfaces
`status.networking.egressCIDRs`). From the control plane, via the Crossplane `Object`:

```bash
kubectl get object.kubernetes.crossplane.io shoot-<name> -o json \
  | jq -r '.status.atProvider.manifest.status.networking.egressCIDRs[]'
```

Enter the bare IPs comma-separated, e.g. `allow_access: 203.0.113.10,203.0.113.11`.

Caveat: the correct value is the source IP **as the database sees it**. If shoot-to-database
traffic leaves via a public NAT, the database observes that public NAT IP, not the private
`egressCIDRs`, and a private-IP allowlist would block the shoots. Confirm by connecting from
inside a shoot (e.g. `curl ifconfig.me` from a pod) and use whichever IP the database
actually receives. `egressCIDRs` can also change if a shoot's infrastructure is recreated.
