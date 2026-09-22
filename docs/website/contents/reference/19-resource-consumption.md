# Resource Consumption

The default Kubernetes resource requests and limits below are shipped with each ODG Helm chart.
They were validated against workloads scanning OCI images up to 6 GiB in size — larger images may require higher limits.

## Default values

A dash (–) means no value is set in the chart (Kubernetes default: unbounded for limits, best-effort for requests).

| Workload | CPU Request | CPU Limit | Memory Request | Memory Limit |
| --- | --: | --: | --: | --: |
| access-manager | 100m | - | 250Mi | 500Mi |
| artefact-enumerator | 250m | – | 200Mi | 1Gi |
| backlog-controller | 250m | – | 100Mi | 250Mi |
| bdba | 250m | – | 500Mi | 1Gi |
| cache-manager | 500m | – | 500Mi | 1Gi |
| clamav | 500m | – | 2Gi | 8Gi |
| codeql | 100m | – | 250Mi | 500Mi |
| crypto | 500m | – | 1Gi | 2Gi |
| delivery-dashboard | 10m | 100m | 10Mi | 100Mi |
| delivery-db | 250m | – | 256Mi | – |
| delivery-db-backup | 500m | – | 500Mi | 1Gi |
| delivery-service | 100m | – | 1Gi | 6Gi |
| freshclam | 100m | – | 500Mi | 1Gi |
| ghas | 250m | – | 250Mi | 500Mi |
| issuereplicator | 1000m | – | 1Gi | 2Gi |
| osid | 250m | – | 250Mi | 500Mi |
| prometheus-operator | 100m | – | 100Mi | 200Mi |
| prometheus-prometheus | 100m | – | 500Mi | 1Gi |
| responsibles | 250m | – | 250Mi | 512Mi |
| sast | 250m | – | 250Mi | 500Mi |
| sbomgenerator | 500m | – | 1Gi | 2Gi |
| sla-violation-profiler | 500m | – | 1Gi | 2Gi |
