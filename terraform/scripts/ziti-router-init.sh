set -o errexit -o nounset -o pipefail

# Retry helper (self-contained — no external dependencies)
retry() {
  local max="$1" delay="$2" desc="$3"; shift 3
  local n=1
  while true; do
    if "$@"; then return 0; fi
    if (( n >= max )); then
      echo "ERROR: $desc failed after $max attempts" >&2; exit 1
    fi
    echo "WARN: $desc failed (attempt $n/$max), retrying in ${delay}s..."
    sleep "$delay"; (( n++ ))
  done
}

ROUTER_NAME="${ZITI_ROUTER_NAME:-zrok2-router}"
JWT_FILE="/ziti-router/${ROUTER_NAME}.jwt"
ZITI_ENDPOINT="https://ziti.${ZROK2_DNS_ZONE}:${ZITI_CTRL_PORT:-1280}"

# Make the shared /ziti-router volume writable by the router's non-root user
# (ziggy, uid 2171). This runs as root; without it the ziti-router container
# cannot write config.yml / enrollment certs into the root-owned volume.
finalize() { chown -R 2171:2171 /ziti-router 2>/dev/null || true; }
trap finalize EXIT

echo "INFO: logging into Ziti controller..."
retry 60 5 "Ziti controller login" \
  ziti edge login "$ZITI_ENDPOINT" \
    --username "${ZITI_USER:-admin}" \
    --password "${ZITI_PWD}" \
    --yes
echo "INFO: logged into Ziti controller"

# skip creation if the router identity already exists (idempotent)
if [[ -f "/ziti-router/${ROUTER_NAME}.cert.pem" || -f "/ziti-router/certs/cert.pem" ]]; then
  echo "INFO: router identity already exists, skipping creation"
  exit 0
fi

_create_router() {
  if ziti edge list edge-routers "name=\"${ROUTER_NAME}\"" 2>/dev/null | grep -q "${ROUTER_NAME}"; then
    echo "INFO: edge router '${ROUTER_NAME}' already exists"
    return 0
  fi
  echo "INFO: creating edge router '${ROUTER_NAME}'..."
  ziti edge create edge-router "${ROUTER_NAME}" \
    --jwt-output-file "$JWT_FILE" \
    --tunneler-enabled
  chmod 0644 "$JWT_FILE"
  echo "INFO: edge router created, JWT saved to $JWT_FILE"
}
retry 5 3 "create edge router" _create_router
