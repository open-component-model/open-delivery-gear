# Overview

Security and compliance shouldn't slow you down. Open Delivery Gear automates scanning, tracking, and reporting across your entire software supply chain, turning compliance from a regular audit into a continuous, automated process. This page will walk you through our motivation and goals, and how ODG helps you deliver secure and compliant software to sovereign clouds around the world.

## Why do we need to change something?

**Compliance is not living next to software. Instead, it is an integral part of it.**

### The Shift from On-Premise to Cloud

Software providers have a long history of on-premise delivery. We built contained software packages, shipped them to customers, and updates came in carefully orchestrated release cycles. When we switched to cloud models, delivery principles fundamentally changed. Patches can now roll out in hours. Teams focus on smaller deliveries with higher frequency.

### The Sovereign Cloud Tension

This shift introduces a critical field of tension for sovereign clouds. On one hand, we have high-frequency delivery practices optimized for speed. On the other hand, sovereign cloud consumers expect contained, self-sufficient deliveries they can trust and operate independently. The air-gap requirement forces sovereign cloud teams to tackle all questions on their own, without the luxury of reaching back to upstream services or support channels.

### Security and Compliance Can't Be an Afterthought

While most teams excel at providing full technical capabilities, **security and compliance often come short**. In sovereign cloud contexts, these must be part of the shipment itself, self-contained and complete. You can't patch security processes after the fact when you're operating in an air-gapped environment.

This becomes even more critical as AI-powered vulnerability research floods development teams with findings. Without top-tier automation and lifecycle processes that allow quick, flexible interaction, teams have no chance to properly assess, prioritize, and remediate these findings at scale.

### The Path Forward

This can only be achieved by **fundamentally changing how we package and deliver software**. Security and compliance must be embedded early in the software lifecycle, making them an integral part of every self-contained shipment. For sovereign cloud deliveries, this isn't optional. It's the only way to maintain both velocity and trust.

### Value Proposition

Open Delivery Gear provides numerous benefits for your software delivery pipeline. Here are some key highlights:

::::{grid} 1 1 2 2
:gutter: 3

:::{grid-item-card} ⚡ Accelerate Compliance
Reduce security finding resolution time through automated scanning, tracking, and GitHub integration. No more manual spreadsheets or status meetings.
:::

:::{grid-item-card} 🎯 Reduce Risk
Continuous monitoring of all OCM components with configurable SLAs ensures vulnerabilities are tracked and resolved before they become incidents.
:::

:::{grid-item-card} 🔍 Full Transparency
Complete visibility into your software supply chain with automated SBOM generation and component tracking across your entire delivery pipeline.
:::

:::{grid-item-card} 🏛️ Sovereign Cloud Ready
Built for sovereign cloud environments with extensible architecture and OCM-native integration for regulated industries.
:::

::::

---

## How we help you with a sovereign cloud delivery

Open Delivery Gear provides an **opinionated end-to-end automation flow** that embeds security and compliance into your delivery lifecycle, without disrupting your existing processes.

### Asynchronous and Non-Blocking

ODG operates asynchronously, pulling in artifacts right after your build completes. Your delivery pipeline continues uninterrupted while ODG schedules specialized agents in the background to perform vulnerability scans, license checks, SBOM generation, and compliance assessments.

### Delivery SLA Tracking

While CI/CD pipelines remain unblocked, teams still need to ensure they're clean from a compliance perspective when they deliver. ODG implements a **delivery tracking mechanism** where findings are tracked according to configurable delivery SLAs. This ensures compliance issues surface in time for teams to address them before releases, without blocking the build itself.

### Intelligent Tracking and Assignment

Once findings are discovered, ODG provides **detailed tracking across the entire lifecycle**. Action items are automatically assigned to individual developer teams based on component ownership. Findings reach the right people without manual triage. No more spreadsheets, no more status meetings. Just clear ownership and accountability.

### Unified Assessment Experience

Developer teams work through a **unified finding assessment experience**, where they can review, prioritize, and remediate security findings in one place. Integration with GitHub means developers can track issues alongside their regular workflow. This reduces context switching and accelerates resolution.

### Audit-Proof Traceability

Every action, assessment, and state change is tracked with **audit-proof traceability and reporting**. When auditors come knocking or compliance reports are due, ODG provides complete visibility into what was scanned, when findings were discovered, who assessed them, and how they were resolved. All automatically generated and ready to share.

---

## What is Open Delivery Gear?

Open Delivery Gear is an **extensible security and compliance engine** designed for sovereign cloud delivery at scale.

### Cloud-Native Architecture

ODG is implemented as a Kubernetes deployment and follows cloud-native principles. It scales with your infrastructure, integrates seamlessly into your existing cloud platforms, and leverages Kubernetes-native patterns for reliability and maintainability.

### Built on Open Component Model

At its core, ODG works with the [Open Component Model (OCM)](https://ocm.software), a standard for describing and packaging cloud-native software artifacts. This gives ODG deep visibility into your component structure, dependencies, and artifact lifecycle, enabling precise tracking and compliance enforcement across complex delivery chains.

### Extensible by Design

ODG's architecture is built for extensibility. Add custom scanners, integrate proprietary compliance tools, or implement organization-specific policies without forking the core platform. The plugin-based scanner framework makes it easy to adapt ODG to your specific security and compliance requirements as they evolve.

---
