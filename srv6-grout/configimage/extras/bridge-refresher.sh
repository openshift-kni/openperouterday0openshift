#!/bin/bash
set -euo pipefail

# bridge-refresher.sh - Mimic the OpenPERouter bridge refresher logic
#
# The full OpenPERouter controller has a bridge refresher that proactively
# resolves ARP for VIPs on the EVPN bridge. Without it, Keepalived GARPs
# on br-ex never create neighbor entries on br-pe-210 in the FRR namespace,
# so EVPN type-2 routes are never advertised and VIPs are unreachable from
# remote PEs. This script fills that gap for rawconfig deployments.

source /etc/openperouter/openperouter.env

: ${REFRESH_INTERVAL:=10}
: ${BRIDGE_NAME:="br-pe-${L2_VNI}"}

# Strip CIDR prefix to get the subnet base for VIP discovery
GATEWAY_SUBNET="${L2_GATEWAY_IP%.*}"

# VIPs to keep alive — API and Ingress
API_VIP="${API_VIP:-${GATEWAY_SUBNET}.10}"
INGRESS_VIP="${INGRESS_VIP:-${GATEWAY_SUBNET}.11}"

# Workaround for FRR #21190: zebra silently ignores FDB notifications
# until advertise-all-vni has taken effect and it knows about the VNI.
# The VLAN bridge port must be added after zebra has learned the VNI,
# otherwise MAC learning events are lost. Fixed in FRR 10.7.
echo "Waiting for zebra to learn VNI ${L2_VNI}..."


while ! podman exec frr vtysh -c "show evpn vni ${L2_VNI}" 2>/dev/null | grep -q "VNI: ${L2_VNI}"; do
	sleep 5
done
echo "VNI ${L2_VNI} discovered"

grcli() {
	echo "+ grcli $*" >&2
	podman exec grout grcli "$@"
}

echo "Bridge refresher started (interval=${REFRESH_INTERVAL}s, bridge=${BRIDGE_NAME})"
echo "  VIPs: $API_VIP, $INGRESS_VIP"

set -x

while true; do
	for vip in "$API_VIP" "$INGRESS_VIP"; do
		#podman exec grout grcli ping "$vip" vrf red count 1 >/dev/null 2>&1 || true
		ping -c 1 "$vip" >/dev/null || true
	done

    # Detect inactive local ARP entries
	# master-0.sno-lab.example.com# show evpn arp-cache vni 210
	# Number of ARPs (local and remote) known for this VNI: 10
	# Flags: I=local-inactive, P=peer-active, X=peer-proxy
	# Neighbor                  Type   Flags State    MAC               Remote ES/VTEP                          Seq #'s
	# fd00:110::3               remote       active   fa:a8:b4:6c:c0:7e 10.0.0.3                                0/0
	# 192.168.110.2             local        inactive c6:11:d0:35:9d:1d                                         0/0
	# fe80::7c2a:cfff:fe06:3bac remote       active   7e:2a:cf:06:3b:ac 10.0.0.4                                0/0
	# fd00:110::2               local        inactive c6:11:d0:35:9d:1d                                         0/0
	# 192.168.110.3             remote       active   fa:a8:b4:6c:c0:7e 10.0.0.3                                0/0
	# fe80::c411:d0ff:fe35:9d1d local        inactive c6:11:d0:35:9d:1d                                         0/0
	# 192.168.110.10            remote       active   7e:2a:cf:06:3b:ac 10.0.0.4                                0/0
	# 
	# see https://github.com/DPDK/grout/issues/741

	if podman exec frr vtysh -c "show evpn arp-cache vni ${L2_VNI}" 2>/dev/null | grep " inactive" >/dev/null; then
		echo "Inactive ARP cache, flushing"
		podman exec grout grcli fdb flush
	fi

	sleep "$REFRESH_INTERVAL"
done
