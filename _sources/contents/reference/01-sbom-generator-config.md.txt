# SBOM-Generator Configuration Reference

The SBOM-Generator extension is configured under the `sbom_generator` key.

## Configuration Example

```yaml
sbom_generator:
  enabled: True
  delivery_service_url: http://delivery-service:5000
  output_format: cyclonedx       # or 'spdx'
  interval: 86400                # re-scan every 24 hours
  mappings:
    - prefix: ''                 # matches all components
      aws_secret_name: ~         # AWS secret name (required for S3 artefacts)
```

## Top-Level Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | bool | `true` | Enable or disable the extension. |
| `delivery_service_url` | string | — | URL of the delivery service instance. |
| `output_format` | string | `cyclonedx` | Output format: `cyclonedx` or `spdx`. |
| `interval` | int (seconds) | `86400` | Maximum time before an artefact is re-scanned. |
| `mappings` | list | `[]` | Per-prefix component mappings. See mapping fields below. |

## Mapping Fields

Each entry in the `mappings` list supports the following fields:

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `prefix` | string | yes | Component name prefix. Use `''` to match all components. |
| `aws_secret_name` | string | no | Name of the AWS secret used to access S3 artefacts. Required when multiple AWS secrets are configured. |

## Configuration Details

### `enabled`

Controls whether the SBOM-Generator extension is active. When set to `false`,
no SBOM generation will occur.

### `delivery_service_url`

The URL where the ODG core service is accessible. This is used to upload
generated SBOMs and record metadata.

### `output_format`

Specifies the SBOM format to generate:
- `cyclonedx`: Generates CycloneDX format SBOMs (default)
- `spdx`: Generates SPDX format SBOMs

### `interval`

The maximum time (in seconds) before a component's artefacts are rescanned.
Default is 86400 seconds (24 hours).

### `mappings`

Allows per-component-prefix configuration. This is particularly useful when:
- Different components require different AWS credentials for S3 access
- You need to handle components from different sources differently

#### Prefix Matching

The `prefix` field uses simple string prefix matching:
- `prefix: 'acme.org'` matches `acme.org/product` and `acme.org/another-product`
- `prefix: ''` (empty string) matches all components (use as a catch-all)

Multiple mappings are evaluated in order, and the first matching prefix is used.

#### AWS Secret Configuration

When scanning S3 resources, the SBOM-Generator needs AWS credentials. The
`aws_secret_name` field specifies which AWS secret to use from your ODG
secrets configuration.

**Example with multiple prefixes:**

```yaml
sbom_generator:
  enabled: True
  delivery_service_url: http://delivery-service:5000
  output_format: cyclonedx
  interval: 86400
  mappings:
    - prefix: 'acme.org/product-a'
      aws_secret_name: aws-account-prod
    - prefix: 'acme.org'
      aws_secret_name: aws-account-dev
    - prefix: ''
      aws_secret_name: aws-account-default
```
