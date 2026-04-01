extensions_cfg:
  defaults:
    delivery_dashboard_url: https://delivery-dashboard.demo.ci.gardener.cloud
    delivery_service_url: https://delivery-service.demo.ci.gardener.cloud
  access_manager:
    enabled: True
  artefact_enumerator:
    components:
      - component_name: ocm.software/ocmcli
  bdba:
    mappings:
      - prefix: ''
        group_id: 2907
  blackduck:
    mappings:
      - prefix: ''
        group_id_bdba: 2907
        targets:
          - group_id: 86cb71af-4bc8-4fbe-beed-4e5731625620
            host: ${blackduck_ctp_url}
          - group_id: f199b865-2b0f-412a-bc11-a190b8e2ee02
            host: ${blackduck_foss_url}
            distribution_mode_overwrite: SAAS
    label_rules:
      - name: ctp-instance
        selector:
          host: ${blackduck_ctp_url}
      - name: foss-instance
        selector:
          host: ${blackduck_foss_url}
  cache_manager:
    prefill_function_caches:
      components:
        - component_name: ocm.software/ocmcli
  clamav:
    mappings:
      - prefix: ''
  crypto:
    mappings:
      - prefix: ''
        standards:
          - name: FIPS
            version: 140-3
            ref:
              path: odg/crypto_defaults.yaml
        libraries:
          - ref:
              path: odg/crypto_defaults.yaml
  ghas:
    github_instances:
      - hostname: github.com
        orgs:
          - open-component-model
  osid:
    enabled: True
  responsibles:
    rules:
      - name: ocmcli
        filters:
          - type: component-filter
            include_component_names:
              - ocm.software/ocmcli
        strategies:
          - type: static-responsibles
            responsibles:
              - type: githubTeam
                github_hostname: github.com
                teamname: open-component-model/maintainers
        assignee_mode: overwrite
  sast:
    enabled: True

findings:
  - type: finding/crypto
    categorisations:
      - id: false-positive
        display_name: False Positive
        value: 0
        rescoring: manual
      - id: security-irrelevant
        display_name: Security Irrelevant
        value: 0
        rescoring: manual
      - id: compliant
        display_name: Compliant
        value: 0
        rescoring: manual
        selector:
          ratings:
            - compliant
      - id: maybe-standard-compliant
        display_name: Maybe Compliant
        value: 2
        allowed_processing_time: 90
        rescoring: manual
        selector:
          ratings:
            - maybe-compliant
      - id: not-standard-compliant
        display_name: Not Compliant
        value: 8
        allowed_processing_time: 30
        rescoring: manual
        selector:
          ratings:
            - not-compliant
    filter:
      - semantics: include
        artefact_kind: resource
  - type: finding/ghas
    categorisations:
      - id: pattern-edited
        display_name: Pattern Edited
        value: 0
        allowed_processing_time: ~
        rescoring: manual
        selector:
          resolutions:
            - pattern_edited
      - id: false-positive
        display_name: False Positive
        value: 0
        allowed_processing_time: ~
        rescoring: manual
        selector:
          resolutions:
            - false_positive
      - id: revoked
        display_name: Revoked
        value: 0
        allowed_processing_time: ~
        rescoring: manual
        selector:
          resolutions:
            - revoked
      - id: wont-fix
        display_name: Won't Fix
        value: 0
        allowed_processing_time: ~
        rescoring: manual
        selector:
          resolutions:
            - wont_fix
      - id: used-in-tests
        display_name: Used In Tests
        value: 0
        allowed_processing_time: ~
        rescoring: manual
        selector:
          resolutions:
            - used_in_tests
      - id: secret-found
        display_name: Secret Found
        value: 2
        allowed_processing_time: 0
        rescoring: manual
        selector:
          resolutions:
            - null
    filter:
      - semantics: include
        artefact_kind: source
  - type: finding/license
    categorisations:
      - id: false-positive
        display_name: False Positive
        value: 0
        allowed_processing_time: ~
        rescoring: manual
      - id: violation
        display_name: Violation
        value: 16
        allowed_processing_time: 0
        rescoring: manual
        selector:
          license_names:
            - sleepycat
    filter:
      - semantics: include
        artefact_kind: resource
  - type: finding/malware
    categorisations:
      - id: false-positive
        display_name: False Positive
        value: 0
        allowed_processing_time: ~
        rescoring: manual
      - id: scanner-limitation
        display_name: Scanner-Limitation
        value: 16
        allowed_processing_time: 0
        selector:
          malware_names:
            - Heuristics.Limits.Exceeded.*
      - id: BLOCKER
        display_name: Found
        value: 16
        allowed_processing_time: 0
        rescoring: manual
        selector:
          malware_names:
            - .*
    filter:
      - semantics: include
        artefact_kind: resource
  - type: finding/osid
    categorisations:
      - id: empty-os-id
        display_name: Empty OS ID
        value: -1
        allowed_processing_time: ~
        selector:
          status:
            - emptyOsId
      - id: no-branch-info
        display_name: No Branch Info
        value: -1
        allowed_processing_time: ~
        selector:
          status:
            - noBranchInfo
      - id: no-release-info
        display_name: No Release Info
        value: -1
        allowed_processing_time: ~
        selector:
          status:
            - noReleaseInfo
      - id: unable-to-compare-version
        display_name: Unable to Compare Version
        value: -1
        allowed_processing_time: ~
        selector:
          status:
            - unableToCompareVersion
      - id: up-to-date
        display_name: Up to Date
        value: 0
        allowed_processing_time: ~
        rescoring: manual
      - id: false-positive
        display_name: False-Positive
        value: 0
        allowed_processing_time: ~
        rescoring: manual
      - id: distroless
        display_name: Distroless
        value: 0
        allowed_processing_time: ~
        rescoring: manual
        selector:
          status:
            - distroless
      - id: postpone
        display_name: Postpone
        value: 1
        allowed_processing_time: input
        rescoring: manual
      - id: one-or-more-patchlevel-behind
        display_name: One or more Patchlevel behind
        value: 2
        allowed_processing_time: ~
        rescoring: manual
        selector:
          status:
            - patchlevelBehind
      - id: eol
        display_name: Branch no longer supported
        value: 8
        allowed_processing_time: 360
        rescoring: manual
        selector:
          status:
            - branchReachedEol
    filter:
      - semantics: include
        artefact_kind: resource
  - type: finding/sast
    default_scope: single
    categorisations:
      - id: other
        display_name: Other
        value: 0
        rescoring: manual
      - id: no-linting-required
        display_name: No SAST scans required
        value: 0
        rescoring: manual
      - id: manual-linting
        display_name: Manual SAST scans done
        value: 0
        rescoring: manual
      - id: missing-linting
        display_name: Missing SAST scan
        value: 16
        allowed_processing_time: 0
        rescoring:
          - automatic
          - manual
        selector:
          sub_types:
            - local-linting
    filter:
      - semantics: include
        artefact_kind: source
    reuse_discovery_date:
      enabled: False
  - type: finding/vulnerability
    rescoring_ruleset:
      cfg_name: gardener
      ref:
        path: odg/defaults.yaml
    categorisations:
      - id: NONE
        display_name: Not Exploitable / Accept
        value: 0 # required to be able to import triages made in BDBA
        rescoring: manual
      - id: postpone
        display_name: Postpone
        value: 1
        allowed_processing_time: input
        rescoring: manual
      - id: LOW
        display_name: Low
        value: 1
        allowed_processing_time: 120
        rescoring: [manual, automatic]
        selector:
          cve_score_range:
            min: 0.0
            max: 3.9
      - id: MEDIUM
        display_name: Medium
        value: 2
        allowed_processing_time: 90
        rescoring: [manual, automatic]
        selector:
          cve_score_range:
            min: 4.0
            max: 6.9
      - id: HIGH
        display_name: High
        value: 4
        allowed_processing_time: 30
        rescoring: manual
        selector:
          cve_score_range:
            min: 7.0
            max: 8.9
      - id: CRITICAL
        display_name: Critical
        value: 8
        allowed_processing_time: 30
        rescoring: manual
        selector:
          cve_score_range:
            min: 9.0
            max: 10.0
    filter:
      - semantics: include
        artefact_kind: resource

features_cfg:
  specialComponents:
    - id: bd545620-3e40-4c7e-aa39-8ef565047c9f
      name: ocm.software/ocmcli
      displayName: OCM CLI
      type: OCM
      version: greatest
      icon: home
      releasePipelineUrl: https://github.com/open-component-model/ocm/actions/workflows/release.yaml
      currentVersion:
        source:
          type: github
          repo: github.com/open-component-model/ocm
          relpath:
            - VERSION
  sprints:
    sprint_name_pattern: '%Y-week-%W'
    start_date: '2026-01-01'
    offset: 0
    cycles: 0
    meta:
      offsets:
        - display_name: Deployment
          name: deployment
          offset_days: 0
        - display_name: Release Decision
          name: release_decision
          offset_days: 0
        - display_name: Pre-Prod Freeze
          name: pre_prod_freeze
          offset_days: -3
  upgradePRs: True

ocm_repo_mappings:
  - type: virtual
    name: <auto>
    selectors:
      - version_filter_overwrite: semver_releases
  - repository: europe-docker.pkg.dev/gardener-project/releases
  - repository: ghcr.io/open-component-model/ocm
    prefixes:
      - ocm.software/ocmcli

profiles:
  - name: OCM
    finding_types:
      - finding/crypto
      - finding/ghas
      - finding/license
      - finding/malware
      - finding/osid
      - finding/sast
      - finding/vulnerability
    special_component_ids:
      - bd545620-3e40-4c7e-aa39-8ef565047c9f
