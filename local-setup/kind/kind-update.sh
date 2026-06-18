#!/usr/bin/env bash

set -euo pipefail

CHART=""

parse_flags() {
  while test $# -gt 0; do
    case "$1" in
    --path-cluster-chart)
      shift; CHART="$1"
      ;;
    esac

    shift
  done
}

parse_flags "$@"

NAMESPACE="${NAMESPACE:-odg}"

ODG_COMPONENT_REF="europe-docker.pkg.dev/gardener-project/releases//ocm.software/open-delivery-gear"
ODG_VERSION="${ODG_VERSION:-$(ocm get cv ${ODG_COMPONENT_REF} --latest -o yaml | yq .[].component.version)}"
COMPONENT_DESCRIPTORS=$(ocm get cv ${ODG_COMPONENT_REF}:${ODG_VERSION} -o yaml --recursive)
echo "Installing Open Delivery Gear with version $ODG_VERSION"

BOOTSTRAPPING_CHART=$(echo "${COMPONENT_DESCRIPTORS}" | yq eval '.[].component.resources.[] | select(.name == "bootstrapping" and .type | test("helmChart")) | .access.imageReference')
DELIVERY_SERVICE_CHART=$(echo "${COMPONENT_DESCRIPTORS}" | yq eval '.[].component.resources.[] | select(.name == "delivery-service" and .type | test("helmChart")) | .access.imageReference')
DELIVERY_DASHBOARD_CHART=$(echo "${COMPONENT_DESCRIPTORS}" | yq eval '.[].component.resources.[] | select(.name == "delivery-dashboard" and .type | test("helmChart")) | .access.imageReference')
EXTENSIONS_CHART=$(echo "${COMPONENT_DESCRIPTORS}" | yq eval '.[].component.resources.[] | select(.name == "extensions" and .type | test("helmChart")) | .access.imageReference')
DELIVERY_DATABASE_CHART=$(echo "${COMPONENT_DESCRIPTORS}" | yq eval '.[].component.resources.[] | select(.name == "postgresql" and .type | test("helmChart")) | .access.imageReference')

kubectl config set-context --current --namespace=$NAMESPACE
kubectl replace -f "${CHART}/crd.yaml"

echo ">>> Installing bootstrapping chart from ${BOOTSTRAPPING_CHART}"
helm upgrade -i bootstrapping oci://${BOOTSTRAPPING_CHART} \
  --namespace ${NAMESPACE} \
  --values ${CHART}/../values.yaml \
  --wait

echo ">>> Installing delivery-database from ${DELIVERY_DATABASE_CHART}"
# First, install custom pv and pvc to allow re-usage of host's filesystem mount
kubectl apply -f "${CHART}/delivery-db-pv" --namespace $NAMESPACE
helm upgrade -i delivery-db oci://${DELIVERY_DATABASE_CHART} \
    --namespace $NAMESPACE \
    --values ${CHART}/values-delivery-db.yaml \
    --wait

echo ">>> Installing delivery-service from ${DELIVERY_SERVICE_CHART}"
helm upgrade -i delivery-service oci://${DELIVERY_SERVICE_CHART} \
    --namespace $NAMESPACE \
    --values ${CHART}/values-delivery-service.yaml \
    --wait
kubectl rollout restart deployment delivery-service # required to use updated configuration
echo "Waiting for delivery-service to become ready, this can take up to 3 minutes..."
kubectl rollout status deployment delivery-service \
    --namespace $NAMESPACE \
    --timeout=180s

echo ">>> Installing delivery-dashboard from ${DELIVERY_DASHBOARD_CHART}"
helm upgrade -i delivery-dashboard oci://${DELIVERY_DASHBOARD_CHART} \
    --namespace $NAMESPACE \
    --values ${CHART}/values-delivery-dashboard.yaml \
    --wait

echo ">>> Installing extensions from ${EXTENSIONS_CHART}"
helm upgrade -i extensions oci://${EXTENSIONS_CHART} \
    --namespace $NAMESPACE \
    --values ${CHART}/values-extensions.yaml \
    --wait

# port-forward to the new delivery-service pods
lsof -i tcp:3000 | grep kubectl | awk 'NR!=1 {print $2}' | xargs kill || true
lsof -i tcp:5000 | grep kubectl | awk 'NR!=1 {print $2}' | xargs kill || true
kubectl port-forward service/delivery-dashboard 3000:8080 > /dev/null &
kubectl port-forward service/delivery-service 5000:8080 > /dev/null &
