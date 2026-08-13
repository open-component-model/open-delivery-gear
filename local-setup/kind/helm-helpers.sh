#!/usr/bin/env bash

# This function populates a global array named HELM_OVERRIDE_ARGS
# with the --values arguments for any local override files that exist.
#
# Usage: build_helm_override_args "/path/to/chart/dir"
build_helm_override_args() {
  # The 'local' keyword makes this variable exist only inside this function.
  local base_dir="$1"

  # HELM_OVERRIDE_ARGS is a global variable by default, so the main
  # script will have access to it after this function runs.
  HELM_OVERRIDE_ARGS=()

  # Define the override files to look for, in order of precedence (last = most important).
  local override_files=(
    "${base_dir}/values-local.yaml"
    "${base_dir}/secrets-local.yaml"
  )

  local found=false
  for file in "${override_files[@]}"; do
    if [ -f "$file" ]; then
      echo ">>> 📋 Using override file: ${file}"
      HELM_OVERRIDE_ARGS+=(--values "$file")
      found=true
    fi
  done

  if [ "${found}" = false ]; then
    echo ">>> ℹ️  No local override files found"
  fi
}
