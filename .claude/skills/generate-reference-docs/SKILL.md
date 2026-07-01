---
name: Generate Reference documentation
description: Translates documentation from bootstrap helm chart values and Python dataclasses to reference documentation on ODG website
---

This skill generates reference documentation pages for ODG extensions by extracting
configuration information from both the upstream values.documentation.yaml file and
the Python dataclass definitions in extensions_cfg.py.

# Invocation

**Generate all extensions:**
```
/ref-docs
```

**Generate a specific extension:**
```
/ref-docs blackduck
/ref-docs artefact_enumerator
/ref-docs ghas
```

When an extension name is provided, only that extension's documentation will be generated or updated.
The extension name should match the key in `extensions_cfg` (e.g., `blackduck`, `artefact_enumerator`, `ghas`).

# Process

1. **Fetch the source data**
   - Read https://github.com/open-component-model/odg-core/blob/master/charts/bootstrapping/values.documentation.yaml
   - Extract the `extensions_cfg` section with field descriptions, types, and defaults
   - Read https://github.com/open-component-model/odg-core/blob/master/src/odg/extensions_cfg.py
   - Extract dataclass definitions for semantic type information, field constraints, and validation rules

2. **Identify entities**
   - If a specific extension name is provided (via skill args), only process that extension
   - Otherwise, process all extensions
   - Each top-level attribute under `extensions_cfg` is one entity
   - Examples: `artefact_enumerator`, `bdba`, `sbom_generator`, etc.
   - Skip the `defaults` key as it's not an extension

3. **Check for meaningful changes (when file exists)**
   - Read the existing documentation file
   - Compare against BOTH the YAML documentation and Python dataclass definitions to identify:
     * **Meaningful changes** (should update): new configuration fields, removed fields, changed types, changed defaults, new sections/tables needed, new field constraints or validation rules
     * **Non-meaningful changes** (should skip): simple rewording, stylistic differences, equivalent descriptions
   - If only non-meaningful differences exist, skip the update and report "No meaningful changes"
   - If file doesn't exist, always create it

4. **Generate and update documentation pages**
   - **IMPLEMENTATION IS REQUIRED**: This skill must actively create/update files using Write/Edit tools
   - For a specific extension: Update file if meaningful changes detected, or create if new
   - For all extensions: Process each extension, updating or creating files as needed
   - Use naming pattern: `NN-{entity-name}-config.md` (where NN is next sequence number)
   - When updating an existing file, preserve the existing sequence number
   - Follow the template structure below
   - **Do not stop at planning** - execute the Write/Edit operations to apply changes

# Template Structure

Each generated page MUST follow this exact format (based on GHAS reference docs):

```markdown
# {Extension Name}

{1-2 sentence description of what this extension does and its purpose}

## Configuration Example

```yaml
{extension_key}:
  {extension-specific fields with realistic example values}
```

## Top-Level Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| {extension-specific options only - EXCLUDE enabled and delivery_service_url} | | | |

## {Additional Field Groups}

If the extension has nested configuration (like mappings, targets, filters), 
create separate sections with tables for those field groups.

Example:
## Mapping Fields

Each entry in the `mappings` list supports the following fields:

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| ... | | | |

## Configuration Details

### {each_configuration_option}

{Detailed explanation with examples where helpful}

{Use #### subheadings for nested concepts within an option}
```

**STOP HERE - Do not add any sections after Configuration Details**

**IMPORTANT: Exclude these standard fields from all documentation:**
- `enabled` - Present in all extensions, not documented individually
- `delivery_service_url` - Present in all extensions, not documented individually

These fields are common infrastructure and should not clutter extension-specific documentation.

# Source Data Integration

The documentation is generated from TWO authoritative sources that complement each other:

## 1. YAML Documentation (values.documentation.yaml)
**Primary use:** Human-readable descriptions, usage notes, examples

**Contains:**
- Field descriptions and purpose
- Usage examples and patterns
- Behavioral notes (e.g., "prefixes are not evaluated as regex")
- Default values (as YAML examples)

## 2. Python Dataclasses (extensions_cfg.py)
**Primary use:** Structural and type information

**Contains:**
- Field types: `str`, `int`, `bool`, `list[str]`, `Optional[str]`, etc.
- Required vs optional fields: `X | None` = optional, `X` = required
- Default values: `field(default=...)`, `field(default_factory=...)`, or `= X` (for static values),
- Type unions: `str | int` means the field accepts either type
- Nested dataclass structures for complex objects
- Field metadata and validation constraints

## How to Use Both Sources

1. **For field types:** Use Python dataclass definitions (more precise than YAML)
2. **For descriptions:** Use YAML documentation (more detailed than code comments)
3. **For required/optional:** Use Python `Optional[X]` typing
4. **For defaults:** Cross-check both; Python is authoritative if they differ
5. **For validation rules:** Check Python dataclass field metadata and validators
6. **For examples:** Use YAML examples, but validate structure against Python types

## Example Integration

Given Python dataclass:
```python
@dataclass
class BDBAConfig:
    enabled: bool = True
    delivery_service_url: str = ''
    interval: int = 86400
    mappings: list[BDBAMapping] = field(default_factory=list)
    on_unsupported: Literal['fail', 'ignore', 'warning'] = 'warning'
```

And YAML documentation:
```yaml
interval:
  description: "Maximum time before a component is re-scanned"
  default: 86400
```

**Generated documentation should combine:**
- Type: `int (seconds)` — from Python type + context
- Default: `86400` — from both sources (confirmed)
- Required: yes — from Python (no Optional)
- Description: "Maximum time before a component is re-scanned" — from YAML

# Critical Template Rules

1. **Title**: Extension name ONLY - NO "Configuration Reference" suffix
2. **Description**: 1-2 sentences max describing WHAT the extension does
3. **Stop after Configuration Details**: This is reference documentation per Diataxis
4. **No sections for**: Use Cases, Best Practices, Troubleshooting, Integration, Security, Migration
5. **Focus on**: Configuration options, their meanings, types, defaults, and how to set them
6. **Examples**: Include realistic YAML examples, use `acme.org` for component names
7. **Subsections**: Use #### for nested concepts within a configuration option (see GHAS `github_instances`)
8. **Tables**: Create separate sections with tables for nested field groups (mappings, targets, etc.)

# Output

After generating each file:
1. Show the filename created or updated
2. Provide a brief summary of the extension's purpose
3. Note any special configuration patterns

**For single extension mode:**
- Report "No meaningful changes" if the existing file already accurately documents the current configuration
- Clearly indicate if the file was updated (and why) or newly created
- Show the extension name that was processed

**For all extensions mode:**
- Skip files that have no meaningful changes
- List all files created or updated with reason
- Provide a summary count at the end (created, updated, skipped)

# Notes

- When invoked without arguments (`/ref-docs`), process all extensions
- When invoked with an extension name (`/ref-docs blackduck`), process only that extension
- The extension name argument should match the YAML key (e.g., `blackduck`, not `BlackDuck`)
- If generating multiple files, process them sequentially to ensure proper numbering
- When updating an existing file, first check for meaningful changes (see step 3)
- Only update files when there are structural/semantic changes, not just rewording
- Use the WebFetch tool to retrieve both the values.documentation.yaml and extensions_cfg.py content
- Cross-reference YAML documentation with Python dataclass definitions for complete type information
- Python dataclasses provide: field types (str, int, bool, Optional, list, etc.), default values, field constraints, Optional vs required fields
- YAML documentation provides: human-readable descriptions, usage notes, examples
- When there's a conflict between YAML and Python definitions, prefer Python for types/structure and YAML for descriptions
- Validate YAML structure and handle missing documentation gracefully
- If the specified extension doesn't exist in the YAML, report an error with available extension names

## Practical Example: Using Both Sources

For the `blackduck` extension:

**From Python (extensions_cfg.py):**
```python
@dataclass
class BlackDuckConfig:
    service: Services = Services.BLACKDUCK
    delivery_service_url: str
    mappings: list[BlackDuckExtensionMapping]
    label_rules: list[BlackDuckLabelRule] = field(default_factory=list)
    interval: int = 86400
    on_unsupported: WarningVerbosities = WarningVerbosities.WARNING

@dataclass
class BlackDuckExtensionMapping(Mapping):
    targets: list[BlackDuckTarget]
    aws_secret_name: str | None
    deduplicate_across_component_versions: bool = True
    cleanup_deprecated_project_versions: bool = False
```

**From YAML (values.documentation.yaml):**
```yaml
blackduck:
  description: "workers that re-upload BDBA results to BlackDuck and retrieve findings"
  interval:
    description: "time in seconds between component re-scans"
    default: 86400
  mappings:
    deduplicate_across_component_versions:
      description: "deduplicates BlackDuck scans of identical artifact versions across component versions"
```

**Combined in documentation:**
- Field `interval`: type `int` (from Python), default `86400` (both), description "time in seconds..." (YAML)
- Field `mappings`: type `list` (Python), contains `BlackDuckExtensionMapping` objects (Python structure)
- Field `deduplicate_across_component_versions`: type `bool` (Python), default `True` (Python), description "deduplicates..." (YAML)
- Field `aws_secret_name`: type `str | None` = optional string (Python), description from YAML
- Field `label_rules`: discovered from Python (not in YAML), type `list[BlackDuckLabelRule]`, default `[]` (empty list)

This reveals that `label_rules` is a field that exists in the code but may not be documented in the YAML - such fields should still be included in the generated documentation.
