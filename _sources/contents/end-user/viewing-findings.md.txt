# How to View Your Findings

## Goal

Find all security and compliance findings you are responsible for in ODG.

## You'll end up with

- A filtered view of all findings assigned to you
- Knowledge of how to prioritize your workload

## Prerequisites

- Access to the ODG Dashboard
- Optionally: Access to GitHub compliance issues
- Assigned responsibility for at least one component

## Choose your path

Select the viewing approach that matches your use case:

::::{grid} 1 1 2 3
:gutter: 3

:::{grid-item-card} 👤 Findings Assigned to Me
:link: viewing-findings.html#option-a

View all findings you are responsible for
:::

:::{grid-item-card} 📖 Findings by Component
:link: viewing-findings.html#option-b

View all findings for a specific component
:::

:::{grid-item-card} 📦 Findings for Next Delivery
:link: viewing-findings.html#option-c

View findings due for a specific delivery milestone
:::

::::

---

(option-a)=
## Option A: View findings assigned to you

Use the Compliance tab to see all findings assigned to you.

### Steps

#### 1. Access the ODG Dashboard

Navigate to the ODG Dashboard and log in.

#### 2. Filter by responsibility

Use the Compliance tab to see your assigned findings.

**In the ODG Dashboard:**

1. Navigate to the **Compliance** tab
2. Tick the **"Filter by responsibility"** checkbox
3. Optionally filter by severity or type

#### 3. Start rescoring process

Select the component you want to check (or all), then click the top-right rescore button to start the rescoring process.

![Compliance View](/_static/odg-compliance-tab.png)

### Alternative: Via GitHub

If your team uses GitHub integration, findings appear as issues.

**In GitHub:**

1. Navigate to your component repository
2. Click the **Issues** tab
3. Look for issues assigned to you

---

(option-b)=
## Option B: View findings by component

Use the Dependencies tab to see all findings for a specific component.

### Steps

#### 1. Access the ODG Dashboard

Navigate to the ODG Dashboard and log in.

#### 2. Navigate to the component

Use the Dependencies tab to find and explore your component.

**In the ODG Dashboard:**

1. Navigate to the **Dependencies** tab
2. Find your component using one of these methods:
   - Select from the left navigation panel
   - Use the custom component search
   - Use the text search on the Dependencies tab
3. Unfold the artefact details
4. Drill into the artefact of interest

#### 3. Review findings and start rescoring

All artefacts are displayed with the most critical finding per category. Use the finding-specific chip to jump into the corresponding rescoring view.

![BOM View](/_static/odg-bom-view.png)

---

(option-c)=
## Option C: View findings for next delivery

Use GitHub milestone view to see findings due for a specific delivery.

### Prerequisites

- Access to GitHub compliance issues
- Your delivery uses GitHub milestones

### Steps

#### 1. Access GitHub

Navigate to your component repository on GitHub.

#### 2. Search for milestone

Use GitHub issue search to find findings for your delivery milestone.

**In GitHub:**

1. Use GitHub issue search to search for the milestone of interest
   - Each milestone maps to one delivery
2. Filter issues with ODG labels (e.g., `vulnerability`, `license`, `malware`)

#### 3. Review finding details

Examine each issue to understand what action is needed.

---

## Related Documentation

- {doc}`rescoring-findings`
- {doc}`assisted-rescoring`
- {doc}`../contributor/concepts/04-responsibles`
