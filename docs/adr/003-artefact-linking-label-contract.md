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

* Companion identity is immediately enumerable from the subject's own label without scanning siblings. No iteration is needed to discover which companions exist.
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
* Consistent with observable practice: existing SBoM-related labels in the ecosystem are already placed on SBoM resources in component descriptors, not on the images they describe.
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

## More Information

### High-level Architecture

Both options use the same label name (`odg.ocm.software/labels/artefact-ref/v1`) and value structure. The only difference is which resource carries the label.

**Option 1 — Forward reference:** the subject artefact lists its companions.

```
Component Descriptor
└── Resource: my-image   ← carries the label, points to my-image-sbom
└── Resource: my-image-sbom
```

**Option 2 — Back reference:** each derived resource points back to its subject.

```
Component Descriptor
└── Resource: my-image
└── Resource: my-image-sbom   ← carries the label, points to my-image
```

### Full Examples

#### Option 1: Forward reference

A multi-arch image declares two companions (an SBoM and an attestation). The label lists them under `companions`:

```yaml
resources:
  - name: my-image
    version: 1.2.3
    type: ociImage
    extraIdentity:
      arch: amd64
    labels:
      - name: odg.ocm.software/labels/artefact-ref/v1
        value:
          companions:
            - artefactReference:
                name: my-image-sbom
              metadata:
                relation: describes
            - artefactReference:
                name: my-image-attestation
              metadata:
                relation: attests

  - name: my-image-sbom
    version: 1.2.3
    type: application/spdx+json

  - name: my-image-attestation
    version: 1.2.3
    type: application/vnd.in-toto+json
```

#### Option 2: Back reference

Each derived resource carries its own label pointing to the subject. The subject itself is not touched:

```yaml
resources:
  - name: my-image
    version: 1.2.3
    type: ociImage
    extraIdentity:
      arch: amd64
    # no label change required on the subject

  - name: my-image-sbom
    version: 1.2.3
    type: application/spdx+json
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

  - name: my-image-attestation
    version: 1.2.3
    type: application/vnd.in-toto+json
    labels:
      - name: odg.ocm.software/labels/artefact-ref/v1
        value:
          artefactReference:
            name: my-image
            version: 1.2.3
            extraIdentity:
              arch: amd64
          metadata:
            relation: attests
```

### Lookup Algorithm for ODG Extensions

#### Option 1: Forward reference

An extension looking for companions of a subject resource reads the label directly from the subject:

1. Find the subject resource in the component descriptor.
2. Check whether it carries a label named `odg.ocm.software/labels/artefact-ref/v1`.
3. If present, read the `companions` list from the label value.
4. For each entry, resolve the companion resource by matching `artefactReference.name` (and `version` / `extraIdentity` if set) against the component's resource list.
5. Optionally filter by `metadata.relation` if only a specific relationship type is needed.

Companion identities are read directly from the subject's label, so no scan is needed to discover them. Resolving each identity to a resource object still requires a lookup against the component's resource list.

#### Option 2: Back reference

An extension looking for companions of a subject resource scans the full resource list:

1. Determine the identity of the subject resource: its `name`, `version`, and `extraIdentity`.
2. Iterate over all resources in the component descriptor.
3. For each resource, check whether it carries a label named `odg.ocm.software/labels/artefact-ref/v1`.
4. If present, compare `artefactReference.name` to the subject's `name` — they must match.
5. If `artefactReference.version` is set, it must match the subject's `version`. If omitted, any version matches.
6. If `artefactReference.extraIdentity` is set, every key-value pair it contains must be present and equal in the subject's `extraIdentity`. If omitted, no extra identity check is applied.
7. Optionally filter by `metadata.relation` if only a specific relationship type is needed.
8. Collect all resources that pass the checks — these are the companions of the subject.

## Decision Outcome

## Conclusion
