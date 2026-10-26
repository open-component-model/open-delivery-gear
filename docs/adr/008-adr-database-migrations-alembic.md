# ADR: Database Migrations with Alembic

| Status   | Proposed   |
|----------|------------|
| Date     | 2026-10-23 |
| Deciders |            |

## Context and Problem Statement

The delivery-service owns the delivery-db schema (tables `artefact_metadata`,
`blob_store`, `cache`, `users`, `user_identifiers`). Since its inception the
schema has been created and "managed" by SQLAlchemy's
`Base.metadata.create_all()` calls in `src/deliverydb/__init__.py`. These run
on every service startup.

`create_all` is not a migration mechanism: it only creates *missing* tables
and silently skips everything else. Concretely:

- Adding a column to an existing table in `model.py` does nothing in
  deployments; the runtime code then errors out on the missing column.
- Type changes, index changes, primary-key changes are never applied.
- Drops require manual SQL in prod.

Combined with the fact that ODG stores most finding payloads as JSON in
`artefact_metadata.data`, the schema drift problem currently shows up as "we
filter JSON in Python after downloading it", which is one of the main
performance and correctness pain points. Any serious schema evolution (proper
columns, types, indexes for the current JSON blobs) requires a real migration
tool.

Alembic in one paragraph: Alembic is the official migration tool of the
SQLAlchemy ecosystem — the ORM ODG already uses everywhere in Python code.
A migration is a small Python file with an `upgrade()` and `downgrade()`
function; alembic stores which of these have been applied in an
`alembic_version` table in the same database. Its distinctive feature
compared to plain-SQL runners is that it can *autogenerate* the migration
file by diffing the Python model classes against the live database. This
means there is exactly one source of truth for the schema (the SQLAlchemy
model classes) instead of two.

## Decision Drivers

- **Reliable schema evolution**: column-level changes must be applicable
  without manual SQL in prod.
- **Standard tooling**: we use SQLAlchemy everywhere; migrations should slot
  into the existing model definitions, not introduce a second source of
  truth.
- **Auditability**: which migrations were applied to a given database must be
  visible (`alembic_version` table).
- **Ops simplicity**: applying migrations must be part of `helm upgrade`,
  not a separate manual step. Failures must be visible and inspectable.
- **Existing deployments**: databases that have been running for a long time
  must be picked up without requiring a dump-and-restore.

## Considered Options

1. **Alembic** — SQLAlchemy's companion migration tool, autogeneration from
   the existing `Base.metadata`, applied via a Helm pre-upgrade Job hook.
2. **Plain SQL migration files + a custom runner** — write `NNNN_*.sql`
   by hand, applied by a small init-container or Job.
3. **Keep `create_all` and hand-migrate** — keep production as-is, run
   manual SQL whenever schema changes are needed.

## Pros and Cons of the Options

### Option 1: Alembic + Helm pre-upgrade Job

Pros:

- Standard tool, native SQLAlchemy integration. `alembic revision --autogenerate`
  detects model changes and produces the migration script from the same
  `Base.metadata` that `create_all` used, so there is **one** source of truth
  for the schema.
- Autogenerate handles the common cases (add/drop column, add/drop table,
  type changes) and warns on what it cannot infer (renames, data migrations).
- Migration history lives in the repo, reviewable via PR.
- `alembic_version` table makes applied state introspectable from any DB.
- Helm pre-install/pre-upgrade hook runs exactly once per release, before
  the new code rolls out. Failures block the rollout — no half-migrated
  state.
- Running migrations repeatedly is safe: `alembic upgrade head` checks the
  `alembic_version` table against the target revision and applies only the
  diff. Retrying a failed upgrade, or redeploying an unchanged chart
  version, is a no-op at the DB level.
- Runs with the same `delivery-db` secret the app uses, no additional
  credentials.

Cons:

- Alembic's autogenerate does not catch renames (it generates
  drop+add). Reviewing generated files is mandatory.
- Adds a small amount of repo/overhead structure (`migrations/` package,
  alembic.ini, bootstrap script).
- Pre-upgrade hook failure blocks the deployment. This is intentional (a
  failed migration must not let new code run against an old schema), but
  requires operators to know about `kubectl logs job/delivery-service-migrate`.

### Option 2: Plain SQL + custom runner

Pros:

- No new dependency.
- Full control over every statement.

Cons:

- Hand-written SQL for every change, including the initial baseline. High
  risk of drift between model definition and migration file.
- No autogenerate, no `alembic_version` table; rolled-back state must be
  tracked by hand.
- We would still need the same Helm Job infrastructure — Option 1's
  operational story without any of its convenience.

### Option 3: Keep `create_all` + manual SQL

Pros:

- Zero code change.
- No new tooling.

Cons:

- The status quo is precisely why this ADR exists; schema changes are
  currently only possible for new tables, everything else is manual,
  unaudited, and forgotten.
- Each environment drifts independently.

## Decision Recommendation

Adopt **Option 1: Alembic + Helm pre-upgrade Job**.

The initial revision is autogenerated from `deliverydb.model.Base.metadata`.
Fresh databases get `alembic upgrade head`; existing `create_all`-era
databases get `alembic stamp head` exactly once, after which all environments
follow the same migration path. The choice between the two is made by a
small bootstrap script (`src/migrations/bootstrap.py`) inside the Job.

### High-level architecture

```
helm upgrade delivery-service
        |
        v
 pre-upgrade hook Job  "delivery-service-migrate"
        |
        +--> python3 -m migrations.bootstrap
                |-- reads delivery-db secret (same as app)
                |-- introspects the database
                |     +-- alembic_version present  -> upgrade head
                |     +-- tables present           -> stamp head
                |     +-- empty                    -> upgrade head
                v
        Job fails? -> Helm marks upgrade as failed.
                      Deployment of new code does not start.
                      Failed Job stays in cluster for `kubectl logs`.
```

**File layout** (in `odg-core`):

```
src/migrations/
  alembic.ini          # file_template with UTC second-precision timestamps
  env.py               # URL resolution: -x db_url, DELIVERY_DB_URL env, or
                       # mounted delivery-db secret
  bootstrap.py         # entry point of the Helm hook Job
  script.py.mako       # revision template
  versions/            # revision files, one per schema change
```

Both `create_all` calls in `src/deliverydb/__init__.py` are removed; Alembic
is the sole owner of the schema. The `migrations` package is shipped as
package data inside the `odg-core-libs` wheel, which the delivery-service
image installs.

### Renames and data migrations

Autogenerated revisions are a starting point; for renames they must be
rewritten by hand to use `op.alter_column(..., new_column_name=...)` etc.
Pure data migrations (no DDL) are written as empty revisions with explicit
`op.execute` / ORM statements.

## Consequences

**Positive:**

- Schema drift becomes visible: running `alembic revision --autogenerate`
  against a deployed DB produces a non-empty revision when drift exists.
- The planned refactor away from "JSON blob + filter in Python" into typed
  columns can now happen incrementally, in reviewable steps.
- Delivery-service pods no longer need DDL privileges at runtime (only the
  migration Job does), which tightens the effective permission surface.
- Backwards/forwards compatibility per release is explicit: the migration
  runs before the new code.

**Negative:**

- Developers must remember to generate and commit a revision with every
  model change. This is only enforceable via code review (and optionally a
  CI drift check in the future).
- Failed migration Jobs block `helm upgrade` until they are resolved and the
  failed Job is deleted (`kubectl delete job delivery-service-migrate -n odg`).
  This is deliberate — this ADR prefers "loud and blocking" over "silent and
  drifting".

**Operational notes:**

- The migration Job reuses the `app: delivery-service` pod label so the
  existing `allow-egress-from-delivery-service` NetworkPolicy applies;
  renaming the label requires adjusting the chart.
- There is intentionally no `helm.sh/hook-delete-policy`, so a failed hook
  keeps its pod and logs available for debugging.
