# ADR: Automated Dependency Updates with Renovate

| Status   | Proposed   |
|----------|------------|
| Date     | 2026-08-12 |
| Deciders |            |

## Context and Problem Statement

> **Note:** This ADR was primarily written based on analysis of `odg-core`. The same problems and decisions apply to other ODG repositories; the scope of rollout is an open question below.

ODG-Core consumes open-source packages at multiple levels - Python runtime dependencies, Dockerfile base images, GitHub Actions, and upstream OCM artefacts declared in `.ocm/base-component.yaml`. Currently none of these are pinned to exact versions:

- `requirements.txt` files list bare package names with no version constraints (addressed by ADR: Python Packaging Migration to uv)
- Dockerfiles use floating tags (`alpine:3`, `golang:alpine`, `mcr.microsoft.com/devcontainers/python:3-3.14-trixie`)
- GitHub Actions workflows reference floating tags (`actions/checkout@v4`, `gardener/cc-utils/...@v1`)
- `.ocm/base-component.yaml` records upstream OCM artefact versions (Helm charts, OCI images) that are updated manually

This means the effective dependency version vector is not fully controlled, creating supply-chain risk and making builds non-reproducible. Dependency drift goes unnoticed until something breaks.

Dependabot is already configured for `pip` and `docker`, but currently provides little value: it has nothing to update for Python because the `requirements.txt` files contain no pinned versions, and it does not cover GitHub Actions. More importantly, it cannot handle `.ocm/base-component.yaml` at all.

## Decision Drivers

- **Supply chain control** - know and pin every dependency version (Ticket 1)
- **Automated bump PRs** - receive PRs when new versions are available rather than discovering drift reactively (Ticket 2)
- **Consistent update policy** - apply the same grouping, cooldown, and auto-merge rules across all dependency types
- **Custom file support** - `.ocm/base-component.yaml` requires a regex-based manager
- **Operational simplicity** - minimize the number of tools and configuration locations

## Considered Options

1. **Extend Dependabot** - already active, zero new tooling
2. **Replace Dependabot with Renovate** - single config covers all four dependency types

## Pros and Cons of the Options

### Option 1: Extend Dependabot

Pros:

- Already running; no new workflow or secrets required
- Native GitHub integration

Cons:

- Cannot update `.ocm/base-component.yaml` - no custom-file / regex manager support
- Does not cover GitHub Actions in this repo
- No Renovate-style dependency dashboard issue covering all configured managers
- Auto-merge and grouping rules are more limited
- uv lockfile support has known unresolved issues in Dependabot

### Option 2: Replace Dependabot with Renovate

Pros:

- Covers all four types: Python/uv lockfile, Dockerfiles, GitHub Actions, `.ocm/base-component.yaml` via regex manager
- `minimumReleaseAge` (e.g. 7 days) prevents merging freshly-published releases; security updates can be configured to bypass the cooldown
- Dependency dashboard issue gives a single overview of all pending updates
- Grouped PRs reduce noise (especially for high-frequency repos like `gardener/cc-utils`)
- Mirrors the pattern already in use in the sibling OCM project
- Auto-merge scoped precisely: patch + minor after cooldown, major bumps require review
- Supports centralized presets if rolled out to multiple repos

Cons:

- Requires a GitHub App with write permissions for contents, PRs, issues, and workflows
- Additional workflow file to maintain

## Decision Recommendation

Adopt **Renovate** to replace Dependabot version-update automation. Renovate will manage all four dependency types. Dependabot security alerts may remain enabled; overlapping Dependabot version-update PRs will be disabled.

### Pinning policy per dependency type

| Type | Pinning target |
|---|---|
| Python | Exact versions + hashes via `uv.lock`; library `[project.dependencies]` use compatible ranges |
| Dockerfile base images | Digest-pinned (`FROM alpine:3.20@sha256:...`), with human-readable tag retained as comment |
| GitHub Actions | SHA-pinned (`uses: actions/checkout@abc123...`); Renovate maintains SHAs automatically |
| `.ocm/base-component.yaml` | Tag-pinned via regex manager; digest pinning TBD pending open question below |

### Auto-merge rules

Auto-merge is allowed only when:
- CI is green and branch protection rules are satisfied
- Update type is patch or minor
- `minimumReleaseAge` has passed (7 days)

Major version bumps always require manual review. Auto-merge will be enabled conservatively after an initial observation period without it.

## Consequences

**Positive:**
- Dependency drift becomes visible through Renovate PRs and the dashboard
- Update policy is centralized in a single `.github/renovate.json5`
- OCM artefact updates become automatable for the first time
- Docker and GitHub Actions dependencies are pinned to immutable references

**Negative:**
- Renovate requires write credentials and a workflow to maintain
- Regex managers for `.ocm/base-component.yaml` need careful testing to avoid incorrect replacements
- Initial rollout will create many update PRs as existing floating references are pinned

## Renovate Configuration Summary

| Setting | Value |
|---|---|
| Workflow | Daily cron, modelled on sibling OCM project's `renovate.yml` |
| Managers | `uv`, `dockerfile`, `github-actions`, `regex` |
| Auto-merge | Patch + minor after `minimumReleaseAge: 7 days` |
| Major bumps | PR only - no auto-merge |
| PR grouping | Non-major updates grouped per ecosystem |
| `gardener/cc-utils` | SHA-pinned, all bumps grouped into one PR (high release cadence) |
| Dry-run on PRs | `RENOVATE_DRY_RUN=extract` when renovate config itself changes |
| Dependency dashboard | Enabled |

## Open Questions

1. **OCI image tag retention in `europe-docker.pkg.dev`** - The Helm chart registry accumulates tags (`10.12.4`, `16.6.1`), but the postgres OCI image registry currently only exposes a single tag (`16.8.0`). If Gardener prunes old image tags, Renovate cannot propose a bump - there is no newer tag to reference. We need to confirm whether this registry accumulates tags over time or replaces them. If tags are pruned, the OCI image entry may need to track the upstream PostgreSQL image on Docker Hub instead.

2. **Registry credentials** - Both `europe-docker.pkg.dev` registries are publicly readable (verified via `crane ls` and `docker pull`). No host rules or secrets are required in the Renovate workflow.

3. **Auto-merge scope for Docker and GitHub Actions** - Minor base image updates can occasionally be disruptive. Auto-merge for these managers should be reviewed after the initial observation period.

4. **Rollout scope and central preset** - This ADR was developed against `odg-core` but the same policy should apply to all ODG repositories. Open questions before broader rollout:
   - Which repos are in scope? A list of affected repositories should be agreed.
   - Should each repo get its own standalone `renovate.json5`, or should we create a shared preset (e.g. `github>open-delivery-gear/renovate-config`) that repos extend with a single line? A central preset makes policy changes easier but adds a dependency. Starting repo-by-repo is lower risk; the preset can be extracted once the config stabilizes.
