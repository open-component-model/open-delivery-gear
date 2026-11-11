# shellcheck shell=bash
# Sourced helper: self-healing kubectl port-forwards for the kind setup.
#
# A plain `kubectl port-forward svc/x` binds to ONE pod and exits when that pod
# goes away (rollout, `kind-local-image`, `observability-on` env patch). The
# loop below restarts it, so forwards survive pod restarts. It exits after 3
# consecutive failed cluster checks (kind-down, reboot, kubeconfig deleted).

# port_forward <kubeconfig> <namespace> <service> <local:remote> <logfile>
# Replaces any existing kubectl port-forward on <local:remote> (incl. a previous
# loop from this helper). Returns 1 if the local port is not bound after 3 s.
port_forward() {
  local kubeconfig="$1" namespace="$2" service="$3" ports="$4" logfile="$5"
  pkill -f "kubectl.*port-forward.* ${ports}" 2>/dev/null || true
  sleep 1
  nohup bash -c '
    fails=0
    while [ "$fails" -lt 3 ]; do
      kubectl --kubeconfig="$1" -n "$2" port-forward "svc/$3" "$4" >>"$5" 2>&1
      kubectl --kubeconfig="$1" get namespace "$2" >/dev/null 2>&1 \
        && fails=0 || fails=$((fails+1))
      sleep 2
    done
    echo "$(date): cluster unreachable 3x - giving up" >>"$5"
  ' "kubectl port-forward ${ports}" "${kubeconfig}" "${namespace}" "${service}" "${ports}" "${logfile}" \
    >/dev/null 2>&1 &
  disown
  sleep 3
  if ! lsof -i "tcp:${ports%%:*}" >/dev/null 2>&1; then
    echo "WARN: port-forward ${ports} for ${service} failed - see ${logfile}" >&2
    return 1
  fi
}

# ODG frontend + backend: :3000 delivery-dashboard, :5000 delivery-service
odg_port_forwards() { # odg_port_forwards <kubeconfig> <namespace>
  port_forward "$1" "$2" delivery-dashboard 3000:8080 /tmp/pf-delivery-dashboard.log || true
  port_forward "$1" "$2" delivery-service 5000:8080 /tmp/pf-delivery-service.log || true
}
