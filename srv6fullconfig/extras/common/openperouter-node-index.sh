#!/usr/bin/env bash
# Set nodeidx as the nodeIndex.interfaceName in  /var/lib/openperouter/node-config.yaml.

set -euo pipefail

NODE_IDX_INTF="${1:-nodeidx}"
CONFIG_PATH="/var/lib/openperouter/node-config.yaml"

echo "Deriving nodeIndex from ${NODE_IDX_INTF}"

mkdir -p "$(dirname "${CONFIG_PATH}")"
cat > "${CONFIG_PATH}" <<EOF
nodeIndex:
  interfaceName: ${NODE_IDX_INTF}
logLevel: debug
EOF
