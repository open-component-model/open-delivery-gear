# Prepare Your Component for ODG

This guide is for component authors who want to get the most out of ODG
scanning. By adding a small set of [OCM labels](../reference/16-ocm-labels.md)
to your component descriptor, you can control scan behaviour, ensure findings
are routed to the right team, and provide context that helps ODG produce more
accurate results.

## Prerequisites

- An OCM component descriptor (`component-descriptor.yaml` or equivalent)
- Familiarity with the [OCM label format](https://ocm.software/docs/reference/component-descriptor/#component-labels)

## Declare Responsible Owners

Add the `cloud.gardener.cnudie/responsibles` label so that ODG and the issue
replicator know whom to assign findings to.

```yaml
labels:
  - name: cloud.gardener.cnudie/responsibles
    value:
      - type: githubTeam
        teamname: my-org/my-team
```

See the [label reference](../reference/16-ocm-labels.md#cloudgardenercnudieresponsibles)
for all supported types (`githubUser`, `codeowners`, `emailAddress`, etc.).

```{note}
The responsibles extension can override or extend these assignments at runtime
via configurable rules. See
{doc}`/contents/concepts/04-responsibles` for details.
```

## Provide CVE Categorisation Context

Add the `gardener.cloud/cve-categorisation` label to describe the deployment
context of your component. ODG uses this to suggest adjusted CVE severity
scores that reflect actual exposure rather than the theoretical maximum.

```yaml
labels:
  - name: gardener.cloud/cve-categorisation
    value:
      network_exposure: "private"
      authentication_enforced: true
      user_interaction: "gardener-operator"
      confidentiality_requirement: "low"
      integrity_requirement: "high"
      availability_requirement: "high"
```

Only set the fields that are meaningful for your component; omitted fields are
treated as unknown and do not affect rescoring. See the
[label reference](../reference/16-ocm-labels.md#gardenercloudcve-categorisation)
for all fields and allowed values.

## Tune or Skip Binary Scans

If ODG runs binary vulnerability scans (BDBA) against your resources, you can
use scan hints to restrict which paths are scanned or to skip a resource
entirely.

```yaml
# on the relevant resource entry
labels:
  - name: cloud.gardener.cnudie/dso/scanning-hints/binary_id/v1
    value:
      policy: "scan"
      path_config:
        include_paths:
          - "^usr/lib/.*"
        exclude_paths:
          - "^usr/lib/debug/.*"
      comment: "Only scan shipped libraries, skip debug symbols"
```

To skip scanning entirely, set `policy: "skip"` and add a `comment` explaining
the reason.

## Mark the Primary Source Repository

Add the `cloud.gardener/cicd/source` label to the source entry that represents
the main repository of your component. ODG uses this for DORA metrics and
GitHub Advanced Security (GHAS) alert ingestion.

```yaml
sources:
  - name: my-repo
    type: github
    access:
      type: github
      repoUrl: github.com/my-org/my-repo
      ref: refs/heads/main
    labels:
      - name: cloud.gardener/cicd/source
        value:
          repository-classification: "main"
```
