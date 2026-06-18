#!/usr/bin/env bash

set -euo pipefail

CLUSTER_NAME=""

parse_flags() {
  while test $# -gt 0; do
    case "$1" in
    --cluster-name)
      shift; CLUSTER_NAME="$1"
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
check_required_flags CLUSTER_NAME

kind delete cluster \
  --name "$CLUSTER_NAME"
