# Open Delivery Gear

**Compliance is not living next to Software; instead, it is an integral part of it.**

Open Delivery Gear (ODG) integrates compliance into the software lifecycle through automated scanning, tracking, and reporting of security findings, vulnerabilities, and compliance issues for your OCM components.

## What is ODG?

Open Delivery Gear is a comprehensive compliance automation platform that:

- **Scans OCM components** for vulnerabilities, license compliance, and security issues
- **Tracks findings** throughout the component lifecycle with configurable processing times
- **Replicates issues** to GitHub for visibility and workflow integration
- **Generates SBOMs** (Software Bill of Materials) for transparency and compliance
- **Manages responsibles** by automatically assigning findings to the right teams

## Key Features

::::{grid} 1 1 2 2
:gutter: 3

:::{grid-item-card} 🔍 Automated Scanning
Continuous scanning of OCI images, source code, and runtime artefacts using industry-standard tools like BDBA, ClamAV, and Syft.
:::

:::{grid-item-card} 📊 Compliance Dashboard
Centralized view of all findings with filtering, sorting, and drill-down capabilities to understand your security posture.
:::

:::{grid-item-card} 🔄 Issue Lifecycle Management
Automatic creation, updating, and closing of GitHub issues based on finding state and processing times.
:::

:::{grid-item-card} 🎯 Responsible Assignment
Intelligent assignment of findings to component owners and teams based on configurable rules and strategies.
:::

::::

## Getting Started

::::{grid} 1 1 3 3
:gutter: 2

:::{grid-item-card}
:class-header: sd-bg-primary sd-text-white

**New Users**
^^^
Start with {doc}`contents/concepts/00-odg-architecture` to understand how ODG works.
:::

:::{grid-item-card}
:class-header: sd-bg-success sd-text-white

**Operators**
^^^
Set up your environment with {doc}`contents/how-to/01-local-setup`.
:::

:::{grid-item-card}
:class-header: sd-bg-info sd-text-white

**Developers**
^^^
Learn to extend ODG with {doc}`contents/tutorial/00-contributing-extension`.
:::

::::

---

## Concepts

*Deep-dive into ODG architecture, data models, and how extensions work*

```{toctree}
:maxdepth: 1
:caption: Concepts

contents/concepts/00-odg-architecture.md
contents/concepts/01-data-model.md
contents/concepts/02-artefact-enumerator.md
contents/concepts/03-issue-replicator.md
contents/concepts/05-responsibles.md
contents/concepts/06-extending.md
contents/concepts/07-sbom-generator.md
```

## How-to Guides

*Step-by-step instructions for common tasks and workflows*

```{toctree}
:maxdepth: 1
:caption: How-to Guides

contents/how-to/00-hybrid-dev-setup.md
contents/how-to/01-local-setup.md
contents/how-to/02-use-odg-api.md
contents/how-to/03-vulnerabilities-for-component.md
contents/how-to/04-diki.md
contents/how-to/05-sbom-download.md
contents/how-to/06-sbom-diagnose-failures.md
```

## Tutorials

*Guided lessons to learn ODG by doing*

```{toctree}
:maxdepth: 1
:caption: Tutorials

contents/tutorial/00-contributing-extension.md
```

## References

*Technical specifications, API documentation, and configuration references*

```{toctree}
:maxdepth: 1
:caption: References

contents/reference/00-artefact-metadata-query.md
contents/reference/01-sbom-generator-config.md
```

---

## Additional Resources

::::{grid} 1 1 3 3
:gutter: 2

:::{grid-item-card} 💻 GitHub Repository
:link: https://github.com/open-component-model/open-delivery-gear
:link-type: url

Source code, issues, and contributions
:::

:::{grid-item-card} 🏗️ ODG Core
:link: https://github.com/open-component-model/odg-core
:link-type: url

Core service implementation
:::

:::{grid-item-card} 📦 Open Component Model
:link: https://ocm.software
:link-type: url

Learn about OCM
:::

::::

```{eval-rst}
.. note::
   This documentation is organized using the `Diataxis framework <https://diataxis.fr/>`_:
   
   - **Tutorials**: Learning-oriented lessons
   - **How-to Guides**: Problem-oriented, goal-focused instructions
   - **Concepts**: Understanding-oriented explanations
   - **References**: Information-oriented technical descriptions
```
