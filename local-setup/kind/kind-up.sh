#!/usr/bin/env bash

set -euo pipefail

CLUSTER_NAME=""
CHART=""

parse_flags() {
  while test $# -gt 0; do
    case "$1" in
    --cluster-name)
      shift; CLUSTER_NAME="$1"
      ;;
    --path-cluster-chart)
      shift; CHART="$1"
      ;;
    esac

    shift
  done
}

check_required_flags() {
  flags=("$@")
  flag_unset=""

  for flag in "${flags[@]}"; do
    [ -z "${!flag}" ] && echo "--$(echo ${flag} | tr '[:upper:]' '[:lower:]' | tr '_' '-') must be set" && flag_unset=true
  done

  [ -n "${flag_unset}" ] && exit 1

  return 0
}

parse_flags "$@"
check_required_flags CLUSTER_NAME CHART

kind create cluster \
  --name "$CLUSTER_NAME" \
  --config <(helm template "$CHART")

NAMESPACE="${NAMESPACE:-odg}"

kubectl create ns $NAMESPACE
kubectl config set-context --current --namespace=$NAMESPACE
kubectl create -f "${CHART}/crd.yaml"

ODG_COMPONENT_REF="europe-docker.pkg.dev/gardener-project/releases//ocm.software/open-delivery-gear"
ODG_VERSION="${ODG_VERSION:-$(ocm get cv ${ODG_COMPONENT_REF} --latest -o yaml | yq .[].component.version)}"
COMPONENT_DESCRIPTORS=$(ocm get cv ${ODG_COMPONENT_REF}:${ODG_VERSION} -o yaml --recursive)
echo "Installing Open Delivery Gear with version $ODG_VERSION"

BOOTSTRAPPING_CHART=$(echo "${COMPONENT_DESCRIPTORS}" | yq eval '.[].component.resources.[] | select(.name == "bootstrapping" and .type | test("helmChart")) | .access.imageReference')
DELIVERY_SERVICE_CHART=$(echo "${COMPONENT_DESCRIPTORS}" | yq eval '.[].component.resources.[] | select(.name == "delivery-service" and .type | test("helmChart")) | .access.imageReference')
DELIVERY_DASHBOARD_CHART=$(echo "${COMPONENT_DESCRIPTORS}" | yq eval '.[].component.resources.[] | select(.name == "delivery-dashboard" and .type | test("helmChart")) | .access.imageReference')
EXTENSIONS_CHART=$(echo "${COMPONENT_DESCRIPTORS}" | yq eval '.[].component.resources.[] | select(.name == "extensions" and .type | test("helmChart")) | .access.imageReference')
DELIVERY_DATABASE_CHART=$(echo "${COMPONENT_DESCRIPTORS}" | yq eval '.[].component.resources.[] | select(.name == "postgresql" and .type | test("helmChart")) | .access.imageReference')

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

kubectl port-forward service/delivery-dashboard 3000:8080 > /dev/null &
kubectl port-forward service/delivery-service 5000:8080 > /dev/null &
