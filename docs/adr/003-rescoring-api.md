# ADR 003: Optimisations for Rescoring API

| Status   | Proposed                                                        |
|----------|-----------------------------------------------------------------|
| Date     | 2026-08-10                                                      |
| Deciders | Alexander Bassmanow, Jonas Brand, Philipp Heil, Chris Schneider |

## Context and Problem Statement

The ODG rescoring API (`GET /rescore`) allows operators to view and override the effective severity of security and compliance findings produced by automated scanners. Findings are immutable records stored in the `artefact_metadata` table; rescorings are overlay records in the same table that shadow findings without mutating them.

For each request the API issues three separate database queries (findings, rescorings, scanner writebacks), then resolves the effective severity for every finding entirely in Python via an O(findings × rescorings) matching loop (`rescorings_for_finding_by_specificity`). Because rescorings can be scoped with wildcard semantics (global, component-wide, artefact-wide, or per-version), the matching query uses `OR (col IS NULL OR col = val)` predicates on seven columns, which are difficult for the database query planner to optimise.

The ODG UI opens a rescoring drawer for one or more artefacts and issues one `GET /rescore` request per artefact concurrently. As the number of artefacts or findings grows, this fan-out pattern amplifies the per-request cost significantly.

The current API also poses challenges for automation and CLI-based workflows. The endpoint accepts only a single artefact per request, making it cumbersome to query rescoring data in bulk. The response schema is deeply nested and tightly coupled to the UI's rendering requirements (including sprint assignments, pending scanner writebacks, and matched rule names), which makes it verbose and inconvenient to consume programmatically. Agents or scripts that only need effective severities must parse a response designed for a rich UI, and must issue one HTTP request per artefact with no way to filter the response to the fields or finding types they actually need.

These characteristics make the API a latency and scalability bottleneck and limit its usability for automated workflows. This ADR evaluates API design changes and performance optimisations to address these issues.

## Decision Drivers

* **Performance** – Reduce query execution time and response latency.
* **Scalability** – Keep the API responsive as data volume grows.
* **Network efficiency** – Limit payload size to what the client actually needs.
* **Operational simplicity** – Optimisations should not introduce excessive operational complexity.
* **Compatibility** - The ODG UI must be able to render the full rescoring view with a single HTTP request per artefact.
* **Bulk request support** – Reduce round‑trips when clients need rescoring data for many artefacts.
* **CLI friendly** - The API should be straightforward to use from scripts and CLI tools without requiring complex query construction or response parsing.
* **Agent friendly** - Automated agents should be able to retrieve only the data they need (e.g. effective severities for specific finding types) without receiving a full UI-oriented response payload.

## Considered Options

### API Design

#### 1. **Support bulk requests for multiple artefacts**

Move the artefact filter from the query parameters to the request body and group the result set by artefact.

*Request Body*
```yaml
schema:
  type: object
  properties:
    artefacts:
      type: array
      items:
        ref: '#/schemas/componentArtefactId'
```

*Response*
```yaml
schema:
  type: object
  properties:
    items:
      type: array
      items:
        type: object
        properties:
          artefact:
            ref: '#/schemas/componentArtefactId'
          findings:
            type: array
            items:
              ref: '#/schemas/rescoringReponse'
```

#### 2. **Support server-side filtering**

Expose filtering options (which are currently implemented in ODG UI) as query parameters.

*Query Parameters*
```yaml
parameters:
  - in: query
    name: dueDate
    required: false
    description: The effective due date of the finding (already considering rescorings).
    schema:
      type: array
      items:
        type: string
  - in: query
    name: severity
    required: false
    description: The effective severity of the finding (already considering rescorings).
    schema:
      type: array
      items:
        type: string
  - in: query
    name: type
    required: false
    schema:
      type: array
      items:
        type: string
        enum:
          - finding/vulnerability
          - ...
```

#### 3. **Support server-side sorting**

Expose sorting options (which are currently implemented in ODG UI) as query parameters.

*Query Parameters*
```yaml
parameters:
  - in: query
    name: orderBy
    required: false
    schema:
      type: string
      default: subject
      enum:
        - finding
        - subject
```

#### 4. **Support pagination**

Expose two additional query parameters (`cursor` and `limit`) to select the current page and to limit the number of items per page. The response includes only the specified number of items as well as the `cursor` for the next page (if any) and the total number of items available.

*Query Parameters*
```yaml
parameters:
  - in: query
    name: cursor
    required: false
    schema:
      type: string
  - in: query
    name: limit
    required: false
    schema:
      type: integer
      default: 50
```

*Response*
```yaml
schema:
  type: object
  properties:
    items:
      type: array
      items:
        ref: '#/schemas/rescoringReponse'
    total_items:
      type: integer
    next_cursor:
      type: string
      nullable: true
```

### Performance Optimisations

#### A. **Use database cache for effective categorisation**
#### B. **Store effective categorisation with finding**
#### C. **Fetch rescorings only once**
#### D. **Run database queries and/or rescoring calculations in parallel**
#### E. **Leverage a database relationship (n:m) for the finding-rescoring relation**
#### F. **Add a new `mapping_key` column which can be used join findings with rescorings**

Similar as done for the `data_key`, the properties which are used as mapping between a finding and the respective rescorings are hashed and stored as extra column `mapping_key` in the database relation (both for findings as well as rescorings). Taking vulnerability findings as an example, those properties are the CVE as well as the package name. An application then joins the findings over the rescorings using this `mapping_key`. However, the rescoring scopes (implemented using the OCM coordinates) still have to be evaluated separately:

```python
import sqlalchemy
import sqlalchemy.orm

import deliverydb
import deliverydb.model
import odg.model


finding = sqlalchemy.orm.aliased(deliverydb.model.ArtefactMetaData, name='finding')
rescoring = sqlalchemy.orm.aliased(deliverydb.model.ArtefactMetaData, name='rescoring')

effective_rescoring = sqlalchemy.select(rescoring).where(
    rescoring.type == odg.model.Datatype.RESCORING,
    rescoring.referenced_type == finding.type,
    rescoring.mapping_key == finding.mapping_key,
    sqlalchemy.or_(
        rescoring.component_name == sqlalchemy.null(),
        rescoring.component_name == finding.component_name,
    ),
    sqlalchemy.or_(
        rescoring.component_version == sqlalchemy.null(),
        rescoring.component_version == finding.component_version,
    ),
    sqlalchemy.or_(
        rescoring.artefact_kind == sqlalchemy.null(),
        rescoring.artefact_kind == finding.artefact_kind,
    ),
    sqlalchemy.or_(
        rescoring.artefact_name == sqlalchemy.null(),
        rescoring.artefact_name == finding.artefact_name,
    ),
    sqlalchemy.or_(
        rescoring.artefact_version == sqlalchemy.null(),
        rescoring.artefact_version == finding.artefact_version,
    ),
    sqlalchemy.or_(
        rescoring.artefact_type == sqlalchemy.null(),
        rescoring.artefact_type == finding.artefact_type,
    ),
    rescoring.artefact_extra_id_normalised == finding.artefact_extra_id_normalised,
).order_by(rescoring.creation_date.desc()).limit(1).correlate(finding).lateral()

result = await db_session.stream(
    sqlalchemy.select(finding, effective_rescoring)
    .outerjoin(effective_rescoring, sqlalchemy.true())
    .where(
        finding.component_name == component_artefact_id.component_name,
        finding.component_version == component_artefact_id.component_version,
        finding.artefact_kind == component_artefact_id.artefact_kind,
        finding.artefact_name == component_artefact_id.artefact.artefact_name,
        finding.artefact_version == component_artefact_id.artefact.artefact_version,
        finding.artefact_type == component_artefact_id.artefact.artefact_type,
        finding.artefact_extra_id_normalised == component_artefact_id.artefact.normalised_artefact_extra_id,
        finding.type.in_(type_filter),
    )
)
```

## Pros and Cons of the Options

### Option 1: Support bulk requests for multiple artefacts

**Pros**
* Reduces request overhead when querying rescoring information for multiple artefacts
* Aligns with the ODG UI which allows rescorings of arbitrary artefact combinations
* Enables CLI tools and agents to fetch rescoring data for many artefacts in a single call
* Rescorings with broad scope (e.g. component-wide) can be fetched once and matched against all requested artefacts, rather than redundantly for each individual request

**Cons**
* Increased complexity of the API route implementation
* Retrieval of necessary rescoring information is more expensive
* The transferred payload size might grow too much
* A single slow artefact (e.g. one with many findings) delays the entire bulk response

### Option 2: Support server-side filtering

**Pros**
* In case filtering is required anyways, it reduces the necessary payload size
* Centralises the filter implementation; easier usage for clients
* Makes the API more useful for automated consumers that only care about a specific finding type or severity range
* Pairs well with Option 1: filtering becomes more important when bulk payloads are large

**Cons**
* Increased complexity of the API route implementation
* Filter parameters must be versioned and documented as part of the public API contract

### Option 3: Support server-side sorting

**Pros**
* Centralises the sorting implementation; easier usage for clients

**Cons**
* Increased complexity of the API route implementation
* Requires complex database queries (sorting by JSON columns based on configuration)
* Makes support of other concepts (i.e. pagination) more difficult
* Sorting criteria depend on finding-type-specific configuration (e.g. severity ordering differs per type), making a generic implementation fragile

### Option 4: Support pagination

**Pros**
* Reduces the transferred payload size
* Depending on the implementation, reduces processing time per request
* Prevents unbounded memory consumption on the server for artefacts with very large numbers of findings

**Cons**
* Increased complexity of the API route implementation
* Might increase the total processing time for all pages
* Increased request overhead when processing multiple pages
* Cursor- or offset-based pagination is difficult to implement correctly when results are sorted by JSON column values (see Option 3)
* Stateless pagination (offset-based) can produce inconsistent results if new rescorings are written between page requests

### Option A: Use database cache for effective categorisation

**Pros**
* Might be used for other API routes as well (e.g. compliance summary)
* Leverages already existing caching infrastructure
* Does not require changes to the data model or the finding immutability contract

**Cons**
* (Possibly complex) cache invalidation will be required
* Updating of existing cache entry takes as long as finding the cache entry

### Option B: Store effective categorisation with finding

**Pros**
* Lookup of effective categorisation is really cheap
* Eliminates the O(findings × rescorings) Python matching loop entirely

**Cons**
* Requires a modification of the data model and related processes (update finding upon rescoring)
* Any change to a broad-scope rescoring (e.g. a component-wide rescoring) requires updating all affected finding rows, which may be a large number of writes
* Introduces write amplification: a single rescoring change triggers updates across potentially many finding records
* During creation of a finding, existing rescorings would need to be evaluated and possibly attached

### Option C: Fetch rescorings only once per API request

**Pros**
* Less database queries required
* Database query does not have to deal with JSON column specifics
* Straightforward to implement without changes to the data model or caching infrastructure
* Naturally composes with Option 1 (bulk): rescorings fetched once can be matched in-memory against findings for all requested artefacts

**Cons**
* All (necessary) rescorings need to be loaded in memory
* Mixup of rescorings to the related artefacts/findings has to be done in memory
* For installations with a large number of broad-scope rescorings, the in-memory set may become significant

### Option D: Run database queries and/or rescoring calculations in parallel

**Pros**
* The available resources can be leveraged more efficiently
* Increasingly complex or larger datasets can be tackled by adding more processing units

**Cons**
* Parallelisation becomes complex when combined with the options outlined for the API design
* Only beneficial if CPU usage is not a bottleneck
* Does not reduce the overall resource requirements to fetch rescorings

### Option E: Leverage a database relationship (n:m) for the finding-rescoring relation

**Pros**
* PostgreSQL databases are known for their high performance, especially when handling large amounts of data and complex queries
* Expensive join operations can be moved from the application into the database layer

**Cons**
* Invasive database adjustments necessary
* Makes it even more difficult to migrate towards non-relational data storage systems

### Option F: Add a new `mapping_key` column which can be used join findings with rescorings

**Pros**
* Allows efficient usage of database join operations as well as indexes
* Follows already existing patterns (e.g. `data_key`)
* `mapping_key` could be used in other contexts as well (e.g. `sla_violations`)

**Cons**
* Requires either a database migration or a legacy code path

## Decision Outcome

Chosen option <X> **"<Option X>"**, because <Explain why this option was chosen and its benefits.>

## More Information

### High-level Architecture

<Provide a diagram or sequence flow if applicable.>

### Contract

<Define the interfaces, protocols, and agreements needed for this decision.>

## Discovery and Distribution

<Explain how the decision will be implemented, distributed, and maintained.>

## Conclusion

<Summarize the decision and its expected impact.>
