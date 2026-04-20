# ADR 001: Scanner Metadata Writeback for Security / Compliance Scanners

| Status   | Proposed                  |
|----------|---------------------------|
| Date     | 2026-04-20                |
| Deciders | Philipp Heil, Jonas Brand |

## Context and Problem Statement

ODG uses scanners like BlackDuck or ClamAV to identify security and compliance related findings for given OCM components.
Most of the scanners follow the same architecture, where one part of the system recognises well-known opensource software, and another one maps opensource software against a metadata database.

ODG treats these scanners as blackboxes, as it just puts in blob data and extracts metadata.
If the scanner-reported properties are faulty (e.g. a package is detected in a wrong version, or an incorrect license is reported), ODG has no means to influence the extracted metadata.

Allowing ODG to write back corrected metadata to scanners raises a conceptional question: **How should ODG collect/store scanner metadata writebacks and how should they be propagated to the scanners?**
Adding a general purpose back channel from ODG to scanners to simply push writebacks is suboptimal because:

* ODG is built around a plugin concept where scanners are exchangeable, the writebacks must live outside of the scanner
* Not every scanner supports metadata writebacks, custom logic is necessary depending on the worker
* ODG intents to abstract away from the scanners, leaking scanner details to ODG users raises a conflict

## Decision Drivers

* **Loose Coupling**: Scanners must remain exchangeable, whereas multiple scanners can be used to produce similar outcomes for the very same input
* **Persistency**: Writebacks must live outside of the scanners so they remain transportable
* **Transparency**: Users must be aware of used writebacks to avoid confusion
* **OCM Label Compatibility**: ODG's writeback mechanism for `finding/vulnerability` must not conflict with Gardener's approach to [OCM-label based package version overwrites](https://github.com/open-component-model/delivery-service/blob/6bd2de7954f02d4c83cf26b23ac46f376417d4be/bdba_utils/scan.py#L281-L299)
* **Reusability**: Writebacks must not only be implemented as custom solution for vulnerabilities, but work in general for all ODG scanner extensions and finding types
* **UX**: There is already a lowlevel package overwrite using OCM labels, thus this approach must focus on UX

## Considered Options

1. **Use Tools directly for Writeback** - Let ODG users navigate into scanner tools and perform metadata corrections directly
2. **Wrap Scanner Writeback API in ODG UI** - Let ODG users perform writebacks in ODG UI, but technically just forward them to the scanner API
3. **Persist Writebacks in ODG, let Worker Implementations consider them** - Store writebacks persistently in ODG database, worker may consider writebacks during worker-loop

## Pros and Cons of the Options

### Option 1: Use Tools directly for Writeback

Pros:

* Already possible via link to the scanner UI, thus no additional implementation efforts
* No additional complexity due to missing handling of writebacks on ODG side

Cons:

* Only possible if the scanner exposes an UI and the ODG user has access to it
* It breaks the claim to establish ODG as the unified, stable interface to address security/compliance requirements
* Since the writebacks would be persisted only on scanner side, they will be lost in case the tooling is changed. However, this might not be too bad since the new tool might be able to detect the correct metadata anyways

### Option 2: Wrap Scanner Writeback API in ODG UI

Pros:

* Keeps ODG as the unified, stable interface to address security/compliance requirements
* Low efforts on the ODG backend side because no additional business logic is required

Cons:

* Requires a scanner specific UI. So far, the ODG UI focused on the finding type as much as possible and neglected which scanner was used to collect the finding information. Implementing scanner specific UIs will make it more difficult to switch underlying tooling
* Since the writebacks would be persisted only on scanner side, they will be lost in case the tooling is changed. However, this might not be too bad since the new tool might be able to detect the correct metadata anyways
* Only possible if the scanner exposes an API for metadata writebacks

### Option 3: Persist Writebacks in ODG, let Worker Implementations consider them

Pros:

* Keeps ODG as the unified, stable interface to address security/compliance requirements
* Allows exchange of the underlying scanner without loss of writebacks
* Allows full control over the desired model structure
* Allows metadata writebacks even if the scanner itself does not provide it out-of-the-box, if there is at least a means of modifying the detected metadata before retrieving the results

Cons:

* High implementation efforts/complexity due to "fullstack integration"
* If the scanner does not allow metadata writebacks, they might still exist in ODG but do not have any effect on the resulting metadata

## Decision Outcome

Chosen option 3 **"Persist Writebacks in ODG, let Worker Implementations consider them"**, because it combines an easy-to-use interface for ODG users while still embracing the loose coupling of scanning tools.
Also, it follows a similar approach than the rescorings which are stored outside of the scanner and therefore allow for a maximum amount of flexibility with regards to their structure.
The difference here, however, is that the writebacks must be written back to the scanner to have an effect on the final metadata.

## More Information

### High-level Architecture

A user of the ODG enters a scanner metadata writeback either via the Delivery Dashboard, or via the Delivery Service API. This results in a (updated) database entry.
A scanner fetches the available writebacks for the scanned artefact via the Delivery Service API.
Per scanner, a custom adapter is required which uses the ODG based writeback to create a scanner specific one.
This must happen _before_ the scan results are fetched and reported into ODG.
As such a writeback only becomes effective once it has been considered by the scanner, a backlog item for the scanner should be created upon submission of a writeback.

### Contract

The model must be flexible enough to cover all applicable finding types, and at the same time simple enough so that it is compatible with all applicable scanners.
While there might be multiple sub types (e.g. package version overwrites vs. license overwrites), there do not have to be coupled to a single specific finding type.
Hence, the overwrites should have a `data.sub_type` property and each worker implementation may only use the overwrites which have a suitable sub type.
The `data.sub_type` field acts as a discriminator that selects which fixed sub-schema applies to the remaining fields in `data`.

#### Scanner Metadata Writeback Model

```yaml
artefact:
  component_name: <str>
  component_version: <str>
  artefact_kind: resource | source
  artefact:
    artefact_name: <str>
    artefact_version: <str>
    artefact_type: <str>
    artefact_extra_id: <object>
meta:
  datasource: delivery-dashboard
  type: meta/scanner_writeback
data:
  sub_type: <str>  # discriminator, e.g. package-version, license
  # remaining fields are fixed per sub_type (see sub-schemas below)
```

#### Sub-Schema: `package-version`

_Compatible with the existing OCM-label based package version overwrite mechanism._

```yaml
data:
  sub_type: package_version
  package_name: <str>
  package_version_from: <str> | null
  package_version_to: <str>
```

_Remarks: In case no `package_version_from` is specified, the `package_version_to` is to be applied to all detected package versions of `package_name`.
In case `package_version_from` is set, the writeback must only be applied to the specified version.
All remaining detected versions must remain unchanged._

#### Sub-Schema: `license`

```yaml
data:
  sub_type: license
  package_name: <str>
  package_version: <str> | null
  license_from: <str> | null
  license_to: <str> | null
```

_Remarks: In case no `package_version` is specified, the `license_to` is to be applied to all detected pacakge versions of `package_name`.
In case no `license_from` is specified, the `license_to` will be **added**.
In case no `license_to` is specified, the `license_from` will be **removed**.
In case both `license_from` and `license_to` are specified, the `license_from` will be **overwritten** by `license_to`.
In case neither `license_from` nor `license_to` are specified, this will be treated as an error._

Additional `sub_type` values may be defined as new use cases occur.
Each gets its own fixed sub-schema documented accordingly.

#### Delivery Service API

To create, fetch and delete scanner metadata writebacks, the already existing `/artefacts/metadata` as well as `/artefacts/metadata/query` routes can be utilised.
In case this does not seem to be convenient enough for the ODG user, a dedicated route might be added at a later point in time.

#### Scanner Metadata Writeback Scope

Writebacks support four scope levels, reusing the same scope mechanism as rescorings.
The scope is expressed by omitting fields in the `artefact` block (set to `null` or empty).
A writeback matches an artefact if every non-null field in its `artefact` block matches the artefact's corresponding field.
The most specific matching writeback takes precedence.
`artefact_kind` and `artefact_type` are always required.

| Scope | Fields omitted | Description |
|---|---|---|
| **Single** | none | Applies to exactly one artefact at a specific component and artefact version |
| **Artefact** | `component_version`, `artefact_version`, `artefact_extra_id` | Applies to all versions of a specific named artefact within a named component |
| **Component** | `component_version`, `artefact_version`, `artefact_extra_id`, `artefact_name` | Applies to all artefacts of a named component, regardless of version |
| **Global** | `component_name`, `component_version`, `artefact_name`, `artefact_version`, `artefact_extra_id` | Applies to all artefacts across all components |

## Discovery and Distribution

In a first step, the data model must be extended as described in this document to allow the persistence of scanner metadata writebacks.
After this initial condition, both the UI integration and the individual adapters for the suitable scanners can be developed independently of each other.
Once new scanning tools are onboarded, it should be evaluated whether they are suitable for writebacks and which `sub_type` sub-schemas they support.
If applicable, the respective adapter should be provided as part of the initial onboarding.
