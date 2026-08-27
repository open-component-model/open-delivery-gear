# Prepare Your Component for ODG

This guide is for component authors who want to get the most out of ODG
scanning. By adding a small set of [OCM labels](../reference/18-ocm-labels.md)
to your component descriptor, you can control scan behaviour, ensure findings
are routed to the right team, and provide context that helps ODG produce more
accurate results.

## Prerequisites

- An OCM component descriptor (`component-descriptor.yaml` or equivalent)
- Familiarity with the [OCM label format](https://ocm.software/docs/reference/component-descriptor/#component-labels)

## Declare Responsible Owners

Add the `odg.ocm.software/responsibles` label so that ODG and the issue
replicator know whom to assign findings to.

```yaml
labels:
  - name: odg.ocm.software/responsibles
    version: v1
    value:
      - type: githubTeam
        teamname: my-org/my-team
```

See the {ref}`label reference <odgocmsoftwareresponsibles-v1>`
for all supported types (`githubUser`, `codeowners`, etc.).

```{note}
The responsibles extension can override or extend these assignments at runtime
via configurable rules. See the
{doc}`/contents/concepts/04-responsibles`
for all fields, allowed values and scopes.
```

## Provide Risk Profile Context

Add the `security.ocm.software/risk-profile` label to describe the deployment
context of your component. ODG uses this to suggest adjusted CVE severity
scores that reflect actual exposure rather than the theoretical maximum.

```yaml
labels:
  - name: security.ocm.software/risk-profile
    version: v1
    value:
      network_exposure: "private"
      authentication_enforced: true
      user_interaction: "end-user"
      confidentiality_requirement: "low"
      integrity_requirement: "high"
      availability_requirement: "high"
```

Only set the fields that are meaningful for your component; omitted fields are
treated as unknown and do not affect rescoring. See the
{ref}`label reference <securityocmsoftwarerisk-profile-v1>`
for all fields, allowed values and scopes.

## Skip Binary or Source Scans

You can configure whether ODG should run binary vulnerability scans or SAST
(Static Application Security Testing) source analysis. Usually `skip` is set
when the pipeline already ran the equivalent scan.

These two labels are **not effective at the component level** — they must be
placed directly on the individual resource or source they control.

```yaml
resources:
  - name: my-image
    ...
    labels:
      - name: odg.ocm.software/binary-scan-policy
        version: v1
        value:
          policy: "skip"
          comment: "Scanned upstream, results attached as SBOM"
sources:
  - name: my-source
    ...
    labels:
      - name: odg.ocm.software/source-scan-policy
        version: v1
        value:
          policy: "skip"
          comment: "We use gosec for SAST scanning, see attached log"
```

See the
{ref}`label reference <odgocmsoftwarebinary-scan-policy-v1>`
for all fields, allowed values and scopes.
