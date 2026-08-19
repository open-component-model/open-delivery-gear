# ADR: Automated Dependency Updates with Renovate

| Status   | Proposed   |
|----------|------------|
| Date     | 2026-08-12 |
| Deciders | Philipp Heil, Alexander Bassmanow |

## Context and Problem Statement

> **Note:** This ADR was primarily written based on analysis of `odg-core`. The same problems and decisions apply to other ODG repositories; the scope of rollout is an open question below.

ODG-Core consumes open-source packages at multiple levels - Python runtime dependencies, Dockerfile base images, GitHub Actions, and upstream OCM artefacts declared in `.ocm/base-component.yaml`. Currently none of these are pinned to exact versions:

- `requirements.txt` files list bare package names with no version constraints (addressed by ADR: Python Packaging Migration to uv)
- Dockerfiles use floating tags (`alpine:3`, `golang:alpine`, `mcr.microsoft.com/devcontainers/python:3-3.14-trixie`)
- GitHub Actions workflows reference floating tags (`actions/checkout@v4`, `gardener/cc-utils/...@v1`)
- `.ocm/base-component.yaml` records upstream OCM artefact versions (Helm charts, OCI images) that are updated manually

This means the effective dependency version vector is not fully controlled and potentially outdated, creating supply-chain risk and making builds non-reproducible. Dependency drift goes unnoticed until something breaks.

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
- Configurable grouped PRs reduce noise
- Mirrors the pattern already in use in the sibling OCM project
- Auto-merge scoped precisely: patch + minor after cooldown (e.g. 7 day period), major bumps require review
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
|CC utils workflows | cc-utils workflows are not updated with renovate but kept at @v1 without further pinning |

### Auto-merge rules

Auto-merge is allowed only when:
- CI is green and branch protection rules are satisfied
- Update type is patch or minor
- `minimumReleaseAge` has passed (7 days)

Major version bumps always require manual review.

The cooldown period is ignored if a CVE for a library gets published.

## Consequences

**Positive:**
- Dependency drift becomes visible through Renovate PRs and the dashboard
- Update policy is centralized in a single `.github/renovate.json5`
- OCM artefact updates become automatable for the first time
- Docker and GitHub Actions dependencies are pinned to immutable references

**Negative:**
- Renovate requires write credentials and a workflow to maintain, so we either need to use or setup an GitHub App.
- Regex managers for `.ocm/base-component.yaml` need careful testing to avoid incorrect replacements
- Initial rollout may create many update PRs as existing floating references are getting pinned
