# ADR: Python Packaging Migration to uv

| Status   | Proposed   |
|----------|------------|
| Date     | 2026-08-12 |
| Deciders | Philipp Heil, Alexander Bassmanow |

## Context and Problem Statement

ODG-Core currently manages Python dependencies via bare `requirements*.txt` files and three `setup.py` build scripts. There is no lockfile, meaning dependency resolution happens at install time and results are not reproducible - two CI runs on different days can install different transitive dependency versions.

The repository publishes three separate PyPI packages from a single source tree: `odg-core-libs` (`setup.py`), `bdba-client` (`setup.bdba-client.py`), and `odg-client` (`setup.odg-client.py`). `odg-core-libs` pins the other two as runtime dependencies. Published library metadata uses bare package names with no version constraints, which is intentional for libraries but means the test/CI/runtime environments are also unpinned.

A lockfile is also a prerequisite for automated dependency update tooling (ADR: Automated Dependency Updates with Renovate) - without pinned versions there is nothing for Renovate to propose bumps against.

## Decision Drivers

- **Reproducibility** - CI, dev, and runtime environments should resolve identical dependency sets
- **Supply chain control** - pinned versions with hash verification
- **Prerequisite for Renovate** - lockfile required for automated Python dependency updates
- **Low operational overhead** - tooling should be fast and not require heavy build infrastructure

## Considered Options

1. **Keep pip, pin versions manually in requirements.txt** - add `==x.y.z` constraints by hand
2. **pip-tools / pip-compile** - generate a `requirements.lock` from existing `requirements.txt` files
3. **uv** - modern Python package manager with native workspace and lockfile support

## Pros and Cons of the Options

### Option 1: Keep pip, pin manually

Pros:

- No tooling change

Cons:
- High manual burden to keep pins current
- Does not compose well with Renovate

### Option 2: pip-tools / pip-compile

Pros:

- Low migration cost - keeps existing `setup.py` / `requirements.txt` structure
- Generates a reproducible `requirements.lock` with hashes

Cons:

- Does not resolve the legacy `setup.py` build structure
- Slower than uv; less actively developed
- uv can also consume `requirements.txt` files, making this a transitional step at best

### Option 3: uv

Pros:

- `uv.lock` with hash verification - fully reproducible installs
- Native workspace support: three packages in one repo with a single lockfile
- Fast (Rust-based); actively developed; now the community standard
- PEP 517 build backend - Can replace `setup.py` with standard `pyproject.toml`
- First-class Renovate manager support

Cons:

- Requires migrating `setup.py` → `pyproject.toml` for all three packages
- Version bumping strategy changes: `setup.bdba-client.py` and `setup.odg-client.py` currently call `bump_minor()` dynamically at build time by reading `VERSION` files; with `pyproject.toml` the version is a static field and the release pipeline must be updated to use `uv version --bump minor` or equivalent
- CI workflows need to switch from `pip install` to `uv sync` / `uv build`

## Decision
Adopt **uv** as dependency manager. For simpler repos we do a full migration (e.g. this repo).

For a complex repo such as `odg-core` a nuanced approach is needed.
A full migration to uv would require many changes in versioning and the downstream build pipelines. 
We will use `uv` as a build-frontend (dependency management, lockfile, virtual env creation) but use the existing build setup with setuptools as the build backend.

## Consequences

**Positive (all):**
- Reproducible installs in CI, dev, and runtime environments
- Hash-verified dependency installation
- Unlocks Renovate's `uv` manager for automated Python dependency updates

**Negative (odg-core):**
- Release pipeline needs updating for the new version bumping approach
- One-time migration effort across three packages and their CI workflows
- Without a full migration, we can't use `uv`s version setting properly
- Need workaround to pin the dependencies in the Dockerfile
