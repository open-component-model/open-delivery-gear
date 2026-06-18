# ADR 003: Artefact-Linking Label Contract

| Status   | Proposed                      |
|----------|-------------------------------|
| Date     | 2026-06-18                    |
| Deciders |                               |

## Context and Problem Statement

OCM resources within a component descriptor are individually addressable but the OCM specification provides no built-in mechanism to express relationships between them. An SBoM resource "belongs to" an OCI image resource, it describes that image but there is no standard way to capture this in the component descriptor.

Multiple ODG extensions need to consume such cross-artefact relationships. The SBoM extension needs to detect pre-provided SBoMs and use them in place of generating new ones. Future extensions will have the same need.

Without a shared, well-defined contract, each extension would invent its own label name and value schema, leading to fragmentation and duplicated lookup logic across the codebase.

The OCM Label API is the appropriate extension point. **How should cross-artefact relationships be expressed via labels so that all ODG extensions interpret them consistently?**

## Decision Drivers

* **Reusability**: The contract must be general enough to serve multiple ODG extensions and relationship types, not only the SBoM case.
* **Alignment with OCM**: The solution must use only the existing OCM Label API.
* **ODG Label Conventions**: Must follow the established label naming conventions already in use.
* **Discoverability**: An ODG extension given a subject artefact must be able to find all resources that relate to it by scanning the component's resource list.
* **Specificity**: The link must be able to target a single artefact variant (e.g. one of several OS/arch-specific images sharing a resource name) via `extraIdentity` matching.

## Considered Options

### Direction of Reference

1. **Label on the subject artefact ("forward reference")** — The primary artefact carries a label pointing to each of its derived resources (e.g. the OCI image labels its own SBoM).
2. **Label on the derived artefact ("back reference")** — The derived resource carries a label pointing to the artefact it relates to (e.g. the SBoM labels the OCI image it describes).

### Label Value Structure

Two approaches were considered for the label value itself:

A. **Flat key-value string** — A single string value encoding only the target resource name with no further structure.
B. **Typed reference object** — A structured object that identifies the target resource by its OCM identity fields (`name`, optional `version`, optional `extraIdentity`) and optionally expresses the relationship type as a `relation` field.

## Pros and Cons of the Options

### Option 1: Label on the subject artefact (forward reference)

Pros:

* Direct lookup: given a subject artefact, the related resources are immediately enumerable from its own labels without scanning siblings.
* Natural from an ownership perspective, the primary artefact declares its companions.

Cons:

* The subject artefact descriptor must be modified every time a new companion is added. This is often not possible when the subject artefact is produced by an independent team or tool.
* Couples the primary artefact to knowledge of all derived resources, violating separation of concerns.
* The label value grows as more companion types are introduced.

Example:

```yaml
resources:
  - name: my-image
    version: 1.2.3
    type: ociImage
    labels:
      - name: odg.ocm.software/labels/artefact-ref/v1
        value:
          companions:
            - name: my-image-sbom
              relation: describes
```

### Option 2: Label on the derived artefact (back reference)

Pros:

* The derived resource is the natural owner of the relationship declaration, an SBoM knows what it describes; the OCI image does not need to know it has an SBoM.
* The subject artefact descriptor does not need to change when a companion is added; the companion resource is produced independently.
* Consistent with observable practice: the `gardener.cloud/sbom/syft` label is already placed on SBoM resources in component descriptors, not on the images they describe.
* Aligns with the principle of least surprise for artefact producers: the relationship travels with the derived resource.

Cons:

* Lookup requires scanning all resources in the component to find those that reference a given subject. This is acceptable given typical component sizes.

Example:

```yaml
resources:
  - name: my-image
    version: 1.2.3
    type: ociImage
    # no label change required on the subject

  - name: my-image-sbom
    version: 1.2.3
    type: application/spdx+json
    labels:
      - name: odg.ocm.software/labels/artefact-ref/v1
        value:
          artefactReference:
            name: my-image
          metadata:
            relation: describes
```

### Option A: Flat key-value string

Pros:

* Short and simple.

Cons:

* If two resources share the same name (e.g. two arch-specific image variants), the string alone is not enough to tell them apart.
* Does not say what kind of relationship exists; the reader has to guess from context.
* Adding more information later would require changing the format.

Example:

```yaml
labels:
  - name: odg.ocm.software/labels/artefact-ref/v1
    value: "my-image"
```

### Option B: Typed reference object

Pros:

* Uses the same fields OCM already uses to identify a resource (`name`, `version`, `extraIdentity`), so there is no new concept to learn.
* Identity fields and metadata (e.g. `relation`) are grouped separately, making the structure easier to extend independently.
* The `relation` field says what the relationship is, without needing a separate label.
* New fields can be added later without breaking existing consumers.
* Matches the pattern used by other ODG labels that also carry structured objects as values.

Cons:

* More to write than a plain string.

Example:

```yaml
labels:
  - name: odg.ocm.software/labels/artefact-ref/v1
    value:
      artefactReference:
        name: my-image
        version: 1.2.3
        extraIdentity:
          arch: amd64
      metadata:
        relation: describes
```

## Decision Outcome

## More Information

### High-level Architecture

### Contract

#### Label Name

#### Full Example

#### Lookup Algorithm for ODG Extensions

## Conclusion
