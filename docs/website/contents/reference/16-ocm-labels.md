# OCM Labels used by ODG

ODG uses [OCM labels](https://ocm.software/docs/reference/component-descriptor/#component-labels) to influence scanning behaviour, CVE rescoring, responsible assignment, and metadata.

---

## `cloud.gardener.cnudie/dso/scanning-hints/binary_id/v1`

Controls whether a binary vulnerability scan is skipped.

```yaml
labels:
  - name: cloud.gardener.cnudie/dso/scanning-hints/binary_id/v1
    value:
      policy: "scan" | "skip"
      path_config:
      include_paths:
        - "^usr/lib/.*"
      exclude_paths:
        - "^usr/lib/debug/.*"
      comment: "free-text string"
```

| Field | Type | Required | Description |
|---|---|---|---|
| `policy` | string | yes | `scan` runs the scan (default behaviour); `skip` bypasses the vulnerability scan for this resource. |
| `path_config.include_paths` | list of regex | no | Only paths matching at least one pattern are included. |
| `path_config.exclude_paths` | list of regex | no | Paths matching any pattern are excluded. Applied after `include_paths`. |
| `comment` | string | no | Human-readable explanation for skipping the scan. |

---

## `cloud.gardener.cnudie/dso/scanning-hints/source_analysis/v1`

Controls whether SAST (Static Application Security Testing) source analysis is run.

```yaml
labels:
  - name: cloud.gardener.cnudie/dso/scanning-hints/source_analysis/v1
    value:
      policy: "scan" | "skip"
      path_config:
        include_paths:
          - "^src/.*"
        exclude_paths:
          - "^src/vendor/.*"
      comment: "free-text string"
```

The fields are identical to those of [`binary_id/v1`](#binary-id-scan-hint).

---

## `cloud.gardener.cnudie/dso/scanning-hints/package-versions`

Use this label to override the package name and version in scan results — for example, to correct cases where the scanner misidentifies a package version inside a binary artefact.

```yaml
labels:
  - name: cloud.gardener.cnudie/dso/scanning-hints/package-versions
    value:
      - name: "package-name"
        version: "1.2.3"
      - name: "another-package"
        version: "4.5.6"
```

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | string | yes | The package name as it appears in the BDBA scan result. |
| `version` | string | yes | The correct version to use in place of the detected one. |

---

## `gardener.cloud/cve-categorisation`

Describes the deployment context of a component or artefact. ODG uses this information to suggest adjusted CVE severity scores that reflect the actual exposure of the component.

All fields are optional. Fields that are omitted are treated as unknown and do not contribute to rescoring decisions.

```yaml
labels:
  - name: gardener.cloud/cve-categorisation
    value:
      network_exposure: "private" | "protected" | "public"
      authentication_enforced: true | false
      user_interaction: "gardener-operator" | "end-user"
      confidentiality_requirement: "none" | "low" | "high"
      integrity_requirement: "none" | "low" | "high"
      availability_requirement: "none" | "low" | "high"
      comment: "free-text string"
```

| Field | Type | Description |
|---|---|---|
| `network_exposure` | string | How reachable the component is from a network perspective. `private`: not reachable from outside a private network. `protected`: reachable from a restricted network or behind authentication. `public`: reachable from the internet |
| `authentication_enforced` | boolean | Whether all access to the component requires authentication |
| `user_interaction` | string | Who interacts with the component. `gardener-operator`: only operators/administrators. `end-user`: arbitrary end users |
| `confidentiality_requirement` | string | How sensitive the data processed by the component is (`none`, `low` or `high`) |
| `integrity_requirement` | string | How critical correct operation of the component is (`none`, `low` or `high`) |
| `availability_requirement` | string | How critical continuous availability of the component is (`none`, `low` or `high`) |
| `comment` | string | Human-readable explanation of the categorisation choices |

---

## `cloud.gardener.cnudie/responsibles`

Explicitly declares who is responsible for a component or artefact.

```yaml
labels:
  - name: cloud.gardener.cnudie/responsibles
    value:
      - type: "githubUser"
        username: "some-github-handle"
        github_hostname: "github.com"    # optional, defaults to github.com
      - type: "githubTeam"
        teamname: "my-org/my-team"
        github_hostname: "github.com"    # optional, defaults to github.com
      - type: "codeowners"
      - type: "emailAddress"
        email: "owner@example.com"
      - type: "personalName"
        firstName: "Jane"
        lastName: "Doe"
```

| Type | Required fields | Description |
|---|---|---|
| `githubUser` | `username` | A specific GitHub user. |
| `githubTeam` | `teamname` | A GitHub team in `org/team` format. |
| `codeowners` | *(none)* | Resolves responsibles from the CODEOWNERS file in the component's source repository. |
| `emailAddress` | `email` | An e-mail address. |
| `personalName` | `firstName`, `lastName` | A person identified by name only. |

---

## `gardener.cloud/purposes`

Tags a resource with a set of named functional purposes. ODG uses this to discover resources that serve a specific role within a component.

```yaml
labels:
  - name: gardener.cloud/purposes
    value:
      - lint
      - sast
      - pybandit
```

Currently the following values are recognised:

| Value | Effect |
|---|---|
| `sast` | The scanned report |

---

## `cloud.gardener/cicd/source`

Marks a source as the primary (main) repository of a component, which ODG can inspect for further analysis such as DORA metrics or security alerts (GHAS).

```yaml
labels:
  - name: cloud.gardener/cicd/source
    value:
      repository-classification: "main"
```

| Field | Type | Required | Description |
|---|---|---|---|
| `repository-classification` | string | yes | Must be `main` if the label is set. |

---

## `cloud.gardener/ocm/creation-date`

Records the creation timestamp of a component. ODG uses this as a fallback when a component descriptor does not populate the `creationTime` field. The creation timestamp is used for further analysis such as DORA metrics or SLA violation profiling.

```yaml
labels:
  - name: cloud.gardener/ocm/creation-date
    value: "2024-06-15T08:30:00.000000+00:00"
```

| Field | Type | Required | Description |
|---|---|---|---|
| `value` | string | yes | ISO 8601 datetime in UTC, e.g. `"2024-06-15T08:30:00.000000+00:00"`. |

---

## `gardener.cloud/comment`

Attaches a free-text comment to a component or artefact.

```yaml
labels:
  - name: gardener.cloud/comment
    value: |
      free-text string
```
