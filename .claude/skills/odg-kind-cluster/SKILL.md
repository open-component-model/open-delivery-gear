---
name: odg-kind-cluster
description: Create, recreate, and check the local ODG kind cluster (kind-odg-local) from the open-delivery-gear repo — picking the ODG release version and enabling the observability stack. Use when spinning up, tearing down, or re-provisioning the local ODG test cluster, testing an ODG release locally, or enabling observability on it.
---

# ODG kind cluster (local testing)

## Repos
Three repos are involved:
- `open-delivery-gear` — cluster management. All `make kind-*` targets run from its root (top-level Makefile).
- `odg-observability` — observability charts. `make kind-observability-on` installs from a sibling checkout by default (override with `ODG_OBSERVABILITY=<path>`).
- `odg-core` — ODG component sources under test.

### Resolve checkout locations BEFORE running anything
Checkout locations differ per developer — never assume them. For each repo, find its root in this order:
1. The current working directory itself, if it is a checkout of that repo.
2. Sibling directories of the current working directory (`../<repo>`).
3. `~/code/github.com/<repo>`, if it exists.
4. Ask the user for the path — do not guess further.
The steps below refer to these roots as "the <repo> root".

## Cluster facts
- kind cluster name `odg-local`, kubectl context `kind-odg-local`.
- The Makefile exports its own `KUBECONFIG` (`local-setup/kind/kubeconfig`), so `make kind-*` works from any shell. For manual kubectl always use `kubectl --context kind-odg-local ...`.
- ODG lands in namespace `odg` (BacklogItems and other CRs live there — NOT the odg-observability chart default `observedNamespace: odg-system`). Set `observedNamespace=odg` when installing the telemetry chart locally.

## 1. Check the cluster is online
```bash
kubectl --context kind-odg-local get ns
```
Connection refused / context missing → cluster is down, recreate it (step 3).

## 2. Pick ODG_VERSION (latest published release)
```bash
gh release list --repo open-component-model/open-delivery-gear --exclude-drafts --exclude-pre-releases --limit 1 --json tagName -q '.[].tagName'
```
The tag is a plain semver with NO `v` prefix (e.g. `0.68.0`) — this matches the Makefile's `ODG_VERSION` format.

## 3. Full recreate flow
Run from the `open-delivery-gear` root:
1. `make kind-down`
2. `ODG_VERSION=<version> make kind-up`
3. Optional, observability work only: `sleep 30` (let the API server and chart installs settle — skipping this regularly breaks step 4), then `make kind-observability-on`.
   Skip it for plain odg-core changes: faster startup, fewer pods, no collector-cluster flake. It is idempotent — run it anytime later on the live cluster when the need shows up.

## 4. Verify before running tests
```bash
kubectl --context kind-odg-local get pods -n odg
```
All pods `Running`/`Completed` → cluster is ready. On `kind-up` failure, check `local-setup/kind/kind-up.sh` logs first, then `kubectl --context kind-odg-local get pods -A`.

## 5. Build and load a local odg-core image
Use this after changing code in `odg-core` to test it on the kind cluster.

1. `cd` to the `odg-core` root
2. `rm -r dist/ && make build-clients && make build-core`
   Output lists built wheels: clients `odg_client`/`bdba_client` (version = `ODG_CLIENT_VERSION` file + one minor bump), core `odg_core_libs` (version from `ODG_CORE_LIBS_VERSION` env or the `VERSION` file). Note the core version.
3. `ODG_CORE_LIBS_VERSION=<core-version> make build-docker-local`
   Local-arch build via buildx `--load` → image `odg-core:<core-version>`.
4. Check the image:
   ```bash
   docker run --rm odg-core:<core-version> python -c "import importlib.metadata as m; print(m.version('odg-core-libs'), m.version('odg-client'), m.version('bdba-client'))"
   ```
5. Load into kind: `kind load docker-image odg-core:<core-version> --name odg-local`
6. Switch cluster workloads, from the `open-delivery-gear` root: `make kind-local-image TAG=<core-version>`
7. Verify: `kubectl --context kind-odg-local get pods -n odg -w` until restarts settle.

### Local client-libs pitfall (verified)
The image does NOT install the locally built `odg_client`/`bdba_client` wheels by default:
- `setup.odg-client.py`/`setup.bdba-client.py` bump one minor (e.g. `0.15.0` → wheel `0.16.0`)
- `odg-core-libs` wheel metadata pins `Requires-Dist: odg-client==0.15.0` (exact pin from root `pyproject.toml` `[project].dependencies`)
- Dockerfile resolves with `--find-links /dist` + PyPI: local `0.16.0` doesn't satisfy `==0.15.0`, so the PUBLISHED client wheel wins
- `constraints.txt` can't help: `uv export --no-emit-workspace` excludes workspace members

**To use the locally built clients if useful / sensible (works today, no Dockerfile change):**
1. Bump the exact pins in root `pyproject.toml` to the bumped client versions (e.g. `odg-client==0.16.0`, `bdba-client==0.16.0`)
2. `uv lock` (required — `uv export --frozen` in the Dockerfile fails when pyproject and lock diverge)
3. Then steps 2 to 6 above. Verify at step 4 that odg-client shows the bumped version.

**Revert the bump before anything gets committed** — those pins and the lock are owned
by the release-client-package workflow; committing the bump breaks the next release:
- Check: `git diff pyproject.toml uv.lock` in odg-core
- If the only changes are the client pins + lock churn: `git checkout -- pyproject.toml uv.lock`
- If the commit needs other pyproject changes: revert ONLY the two pin lines, then `uv lock`
Repeat the bump after every revert when testing again (it does not survive `git checkout`).

**Why a plain Dockerfile ARG can't fix this:** the `==` pin is baked into the core wheel's metadata at build-core time; an install-time ARG (e.g. `USE_LOCAL_CLIENTS`) would need the Dockerfile to install clients first + core with `--no-deps`, or odg-core to stop pinning exactly. If a permanent switch is wanted, change pyproject not to pin clients exactly, then add the ARG.

## 6. Verify changes after image swap / observability-on
Run these against `kubectl --context kind-odg-local`, namespace `odg`.

### a) All pods up
```bash
kubectl --context kind-odg-local get pods -n odg
```
Known flake: `telemetry-opentelemetry-collector-cluster-*` sometimes hangs on startup (ContainerCreating/0 restart, no progress). Fix: delete the pod by name — the Deployment recreates it healthy. Don't debug it.
Pod stuck elsewhere: check `kubectl --context kind-odg-local logs <pod> -n odg --previous` for the crash reason before deleting.

### b) Logs look expected
```bash
kubectl --context kind-odg-local logs -n odg deploy/delivery-service --tail=100
kubectl --context kind-odg-local logs -n odg <pod-of-your-change> --tail=100
```
Looking for: clean startup, no tracebacks, no repeated ERROR/refused-connection loops. Errors during the first seconds after an image pull are fine if the pod then settles.

### c) Trigger cronjobs manually (don't wait for the schedule)
Existing cronjobs: `access-manager`, `cache-manager` (*/10), `artefact-enumerator` (*/5), `ghas`, `sla-report`, `sla-violation-profiler` (daily). Trigger the one(s) your change touches:
```bash
kubectl --context kind-odg-local create job -n odg --from=cronjob/artefact-enumerator manual-enumerator-$(date +%s)
kubectl --context kind-odg-local logs -n odg -l job-name=manual-enumerator-<ts> --tail=100 -f
kubectl --context kind-odg-local delete job -n odg manual-enumerator-<ts>   # job pods linger otherwise
```
Expected: job completes, exit 0, no tracebacks in its logs.

### d) Observability testing → create BacklogItems inline
Skip unless the change touches telemetry (logs/metrics/Metric CRs/dashboards) or `kind-observability-on` was run. Needs the observability stack up (section 3, step 4).
Fixtures live as examples (committed state format) in `bli/` in the `odg-observability` repo — do NOT commit cluster fixtures; create them inline. Minimal valid BLI (from the examples):
```bash
kubectl --context kind-odg-local apply -f - <<EOF
apiVersion: delivery-gear.gardener.cloud/v1
kind: BacklogItem
metadata:
  name: blackduck-test-1
  namespace: odg            # the ns the metrics-operator scopes to
  labels:
    delivery-gear.gardener.cloud/service: blackduck   # sbomGenerator | issueReplicator | bdba
    # delivery-gear.gardener.cloud/claimed: "True"    # add on some items
spec:
  artefact:
    artefact:
      artefact_extra_id: {}
      artefact_name: helm-controller
      artefact_type: ociImage
      artefact_version: v1.6.5-test
    artefact_kind: resource
    component_name: github.com/gardener/gardener-landscape-kit
    component_version: v0.8.0
    references: []
  priority: 1               # 0 NONE 1 LOW 2 MEDIUM 4 HIGH 8 CRITICAL
  timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
```
For namespace-scoping tests: ~10 in `odg`, ~5 in another ns (e.g. `delivery`, create it first), mixed services/priorities. Loop the heredoc with a for-loop; vary `name`, `service`, `priority`, drop in the claimed label on some.
Then verify the series:
```bash
kubectl --context kind-odg-local get svc -n odg | grep metrics     # telemetry-metrics-operator service
kubectl --context kind-odg-local port-forward -n odg svc/<metrics-svc> 8080:8080 &
curl -s localhost:8080/metrics | grep odg_backlogitems
kubectl --context kind-odg-local get backlogitems -n odg --no-headers | wc -l  # series total must equal THIS, not -A
```

### e) Verify YOUR change specifically
After the generic a)d checks pass: test the exact behavior you changed (e.g. Metric CR namespace scoping → `odg_backlogitems` totals match `-n odg`, not `-A`; code change → exercise the API/path it touches end-to-end). Series need up to 2 scrape intervals (~2 min at interval 1m) to update — don't judge stale data.

## 7. Access the observability stack (ports from observability-on)
Only available after `make kind-observability-on` ran — skip entirely for plain odg-core change tests.
`make kind-observability-on` sets up self-healing kubectl port-forwards (see `local-setup/kind/port-forwards.sh` — they survive pod restarts + image swaps):
| localhost | target | use |
|---|---|---|
| :9090 | prometheus-operated | PromQL checks, e.g. `odg_backlogitems` |
| :8080 | perses | dashboards UI (queries prometheus) |
| :5601 | opensearch-dashboards | Discover UI; index patterns `logs-otel-v1` (logs), `traces-otel-v1` (spans) |
| :4317 | otel-collector svc | OTLP ingress for locally run apps (see `make kind-otlp-env`) |
| :3000 / :5000 | delivery-dashboard / delivery-service | ODG UI + API |

Flow: collector daemonset pushes logs+traces → opensearch :9200 (in-cluster); prometheus :9090 scrapes collector :8889; perses :8080 queries prometheus.

If a forward is dead: `lsof -i tcp:<port>` and `/tmp/pf-*.log`. Cause is usually kind-down/reboot (helper gives up after 3 failed cluster checks) — re-run `make kind-observability-on` (idempotent), or re-create one forward as in port-forwards.sh.
Ad-hoc: collector metrics exporter isn't forwarded — `kubectl --context kind-odg-local port-forward -n odg svc/telemetry-opentelemetry-collector 8889:8889` then `curl -s localhost:8889/metrics`.
On-the-pod alternative: `kubectl --context kind-odg-local exec -n odg statefulset/opensearch -- curl -s localhost:9200/_cat/indices` (same pattern for other pods).
