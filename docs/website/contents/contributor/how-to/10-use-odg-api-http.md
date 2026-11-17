# Use HTTP to resolve an OCM component

## Goal

Resolve an OCM component using the ODG API and curl.

## You will end up with

- a bash script calling the ODG API to resolve an OCM component

## Prerequisites

- An ODG instance
- `curl`
- A (unprivileged) fine-grained GitHub token for a user authorised with read-access to the ODG instance

## Actions

### Authenticate

```bash
ODG_API=https://delivery-service.demo.ci.gardener.cloud
GH_TOKEN=github_pat_xxx
GH_API=https://api.github.com
auth_cookie_path="auth_cookie.txt"

curl \
    -X POST \
    -s \
    -c "${auth_cookie_path}" \
    --json "{
    \"api_url\": \"${GH_API}\",
    \"access_token\": \"${GH_TOKEN}\"
  }" "${ODG_API}/auth"
```

### Resolve OCM component

An OCM component is resolved via `GET /ocm/component` endpoints, which features parameters like `component-name` and `ocm-repo`.
The corresponding bash implementation to resolve the OCM component `acme.org/sovereign/postgres` in a certain version looks like this.

```bash
component_name=acme.org/sovereign/postgres
component_version=1.0.0
component_descriptor=$(curl \
    -s \
    -b "${auth_cookie_path}" \
    "${ODG_API}/ocm/component?component_name=${component_name}&version=${component_version}"
)
```
