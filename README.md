<p align="center">
	<img src="resources/odg.svg" alt="Open Delivery Gear Logo" />
</p>

<h1 align="center">Open Delivery Gear</h1>

Open Delivery Gear (ODG) is a production-ready compliance automation engine built for software components modelled with the [Open Component Model](https://ocm.software).
It helps teams continuously scan delivery artifacts, keep findings actionable, and enforce service-level expectations through automation.
ODG implements a trust-but-verify solution for public and **sovereign clouds**.

The project is under neutral governance by the [NeoNephos Foundation](https://neonephos.org), as part of the [Apeiro Reference Architecture](https://apeirora.eu).

[![REUSE status](https://api.reuse.software/badge/github.com/open-component-model/open-delivery-gear)](https://api.reuse.software/info/github.com/open-component-model/open-delivery-gear)
[![OpenSSF Baseline](https://www.bestpractices.dev/projects/12270/baseline)](https://www.bestpractices.dev/projects/12270)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/open-component-model/open-delivery-gear/badge)](https://scorecard.dev/viewer/?uri=github.com/open-component-model/open-delivery-gear)

## Index

- [What Is It?](#what-is-it)
  - [How Does It Work?](#how-does-it-work)
  - [Look and Feel](#look-and-feel)
- [Getting Started](#getting-started)
- [Community](#community)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [Licensing](#licensing)

## What Is It?

ODG is an extensible security and compliance automation toolbox designed for cloud-native delivery and Kubernetes-centric environments.

**Core capabilities include**:

- Kubernetes-native deployment and operating model
- Asynchronous and autonomous security and compliance scans
- Extensible architecture for custom integrations and policies
- Finding tracking with configurable SLAs
- "Trust, but verify" operating model for delivery assurance
- Assisted rescoring to extract value from available runtime context information

The goal is to reduce manual governance effort while increasing confidence in software delivery quality and compliance posture across public and sovereign cloud scenarios.

### How Does It Work?

Open Delivery Gear follows an automation-first workflow:

- Users subscribe to OCM component versions.
- Scans are executed automatically and asynchronously.
- Scanner capacity scales both vertically and horizontally.
- Findings are tracked against discovery dates and SLA timelines.
- Assisted rescoring can adjust due dates or classify findings as false positives.
- Processing remains traceable and transparent.
- Assessments can be transported and imported via OCM.

### Look and Feel

Open Delivery Gear is designed for both platform operators and application teams.
Operators interact with ODG through the Kubernetes API to integrate it into cluster-native workflows.
End users can work with findings and delivery insights either through the Delivery Dashboard UI or via HTTP APIs for automation and integration scenarios.

![Delivery Dashboard](resources/delivery-dashboard.png)

## Getting Started

- [Local Setup using Kind](https://github.com/open-component-model/delivery-service/blob/master/local-setup/local-setup.md)
- [Standalone installation using Helm](https://github.com/open-component-model/delivery-service/tree/master/charts)
- [K8s ODG Operator](https://github.com/open-component-model/delivery-service/tree/master/odg_operator)
- [🚧 openMCP Provider](https://github.com/openmcp-project)

<details>
  <summary>Related Repositories and Codebases</summary>

### Core Components and Extensions

The codebase is distributed across multiple repositories.

#### delivery-service

##### Core APIs

- [Core API](https://github.com/open-component-model/delivery-service/blob/master/app.py)
- [ODG Database](https://github.com/open-component-model/delivery-service/tree/master/deliverydb)
- [ODG Operator](https://github.com/open-component-model/delivery-service/tree/master/odg_operator)
- [OCM Artefact Enumerator](https://github.com/open-component-model/delivery-service/blob/master/artefact_enumerator.py)
- [Assisted Rescoring](https://github.com/open-component-model/delivery-service/tree/master/rescore)
- [Scan Backlog Controller](https://github.com/open-component-model/delivery-service/blob/master/backlog_controller.py)
- [ODG Database Backup](https://github.com/open-component-model/delivery-service/blob/master/delivery_db_backup.py)

##### Extensions

- [Cryptographic Asset Inventory](https://github.com/open-component-model/delivery-service/tree/master/crypto_extension)
- [Vulnerability Scanner (BDBA)](https://github.com/open-component-model/delivery-service/tree/master/bdba)
- [GitHub Issues-Based Finding Tracker](https://github.com/open-component-model/delivery-service/tree/master/issue_replicator)
- [Malware Scanner (ClamAV)](https://github.com/open-component-model/delivery-service/tree/master/malware)
- [Operating System EoL Detection](https://github.com/open-component-model/delivery-service/tree/master/osid_extension)
- [DORA Metrics](https://github.com/open-component-model/delivery-service/blob/master/dora.py)
- [GitHub Secret Scanner](https://github.com/open-component-model/delivery-service/blob/master/ghas.py)
- [SBoM Generator](https://github.com/open-component-model/delivery-service/blob/master/sbom_generator.py)

#### delivery-dashboard

- [ODG User Interface](https://github.com/open-component-model/delivery-dashboard)

#### cc-utils

- [OCM Language Bindings](https://github.com/gardener/cc-utils/tree/master/ocm)
- [OCI Client](https://github.com/gardener/cc-utils/tree/master/oci)
- [ODG Core API Client](https://github.com/gardener/cc-utils/tree/master/delivery)

#### odg-prometheus

- [Monitoring Stack](https://github.com/open-component-model/prometheus)

</details>

## Community

Open Delivery Gear is part of the [OCM community](https://ocm.software/community/engagement/).

- Join the regular OCM community call to discuss roadmap topics, integrations, and operational best practices.
- Use community discussions to share feedback, report gaps, and collaborate on new automation scenarios.

## Documentation

- [Technical Documentation](https://open-component-model.github.io/delivery-service/)
- [ODG Project Board](https://github.com/orgs/open-component-model/projects/17)

## Contributing

Code contributions, feature requests, bug reports, and help requests are very welcome. Please refer to the
[Contributing Guide in the Community repository](https://github.com/open-component-model/.github/blob/main/CONTRIBUTING.md)
for more information on how to contribute to ODG.

To make ODG a welcoming and harassment-free experience for everyone, we follow the [NeoNephos Code of Conduct](https://github.com/neonephos/.github/blob/main/CODE_OF_CONDUCT.md).

## Licensing

Please refer to the [LICENSE](LICENSE) for copyright and license information.
Detailed information, including third-party components and their licensing/copyright information is available
[via the REUSE tool](https://api.reuse.software/info/github.com/open-component-model/open-delivery-gear).

---

<p align="center"><img alt="Bundesministerium für Wirtschaft und Energie (BMWE)-EU funding logo" src="https://apeirora.eu/assets/img/BMWK-EU.png" width="400"/></p>
