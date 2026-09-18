# OpenPERouter Network Topology — ISIS + SRv6

## Overview

An ISIS + SRv6 fabric running on top of an OpenShift cluster (3 masters + N workers),
with a TOR router peering externally.

- **Underlay**: ISIS Level-1 (IPv6-only), single area `49.0001`
- **L3VPN** (north-south): BGP IPv4/IPv6 VPN with SRv6 encapsulation between all nodes and the TOR
- **L2VPN** (east-west): BGP EVPN with VXLAN (VNI 210) between all cluster nodes, reflected by all 3 masters
- **AS**: 65500 (all iBGP)

```
                       ┌──────────────────────────────┐
                       │        TOR / RemotePE        │
                       │   Router ID: 10.0.0.20       │
                       │   Loopback:  fc00:0:20::1    │
                       │   SRv6 pfx:  fd00:20::/48    │
                       │   VRF red:                   │
                       │     lored:    10.10.20.1/32  │
                       │     lo-extra: 10.100.0.1/32  │
                       │       (DNS + NTP server)     │
                       └──────────┬───────────────────┘
                                  │ ISIS L1 (IPv6-only)
                                  │ enp2s0 (192.168.111.0/24
                                  │         fd2e:6f44:5dd8:c956::/120)
                 ┌────────────────┼────────────────┐
                 │                │                │
     ┌────────────────┐   ┌────────────────┐   ┌────────────────┐
     │  master-0      │   │  master-1      │   │  master-2      │
     │----------------│   │----------------│   │----------------│
     │  EVPN RR       │   │  EVPN RR       │   │  EVPN RR       │
     │  SRv6:         │   │  SRv6:         │   │  SRv6:         │
     │   fd00:2:2::/48│   │   fd00:2:3::/48│   │   fd00:2:4::/48│
     │----------------│   │----------------│   │----------------│
     │Host Netns:     │   │Host Netns:     │   │Host Netns:     │
     │  br0/br-ex:    │   │  br0/br-ex:    │   │  br0/br-ex:    │
     │  .110.2        │   │  .110.3        │   │  .110.4        │
     │----------------|   │----------------|   │----------------|
     │perouter Netns: │   │perouter Netns: │   │perouter Netns: │
     │  lo:  fd00::2  │   │  lo:  fd00::3  │   │  lo:  fd00::4  │
     │  enp2s0:       │   │  enp2s0:       │   │  enp2s0:       │
     │  .111.80       │   │  .111.81       │   │  .111.82       │
     │  ::50          │   │  ::51          │   │  ::52          │
     │                │   │                │   │                │
     │  VRF red:      │   │  VRF red:      │   │  VRF red:      │
     │   br-pe-210    │   │   br-pe-210    │   │   br-pe-210    │
     │   .110.1/24    │   │   .110.1/24    │   │   .110.1/24    │
     │   VNI 210      │   │   VNI 210      │   │   VNI 210      │
     └────────────────┘   └────────────────┘   └────────────────┘
           ▲                   ▲                   ▲
           └─── EVPN RR mesh ──┴─── EVPN RR mesh ──┘

     ┌────────────────┐   ┌────────────────┐
     │  worker-0      │   │  worker-1      │   ...
     │----------------│   │----------------│
     │  EVPN Client   │   │  EVPN Client   │
     │  SRv6:         │   │  SRv6:         │
     │   fd00:2:5::/48│   │   fd00:2:6::/48│
     │----------------│   │----------------│
     │Host Netns:     │   │Host Netns:     │
     │  br0/br-ex:    │   │  br0/br-ex:    │
     │  .110.5        │   │  .110.6        │
     │----------------|   │----------------|
     │perouter Netns: │   │perouter Netns: │
     │  lo:  fd00::5  │   │  lo:  fd00::6  │
     │  enp2s0:       │   │  enp2s0:       │
     │  .111.83       │   │  .111.84       │
     │  ::53          │   │  ::54          │
     │                │   │                │
     │  VRF red:      │   │  VRF red:      │
     │   br-pe-210    │   │   br-pe-210    │
     │   .110.1/24    │   │   .110.1/24    │
     │   VNI 210      │   │   VNI 210      │
     └────────────────┘   └────────────────┘
           ▲                   ▲
           └── EVPN clients ───┘
          (peer with all 3 masters)
```

## Addressing Scheme

Bridge, loopback, router ID, and SRv6 locator addresses are derived from the node
index — the host position within the `192.0.2.0/24` subnet on the `nodeidx` dummy
interface (e.g. `192.0.2.2` → index 2). For these, the node address is simply the
subnet base + node index.

The `enp2s0` addresses (ISIS underlay interface) are assigned statically in the
agent-config and do not follow the node index scheme.

Node types are derived from the node's hostname (if it starts with `master` or `control-plane`,
the node is of type `master`).

| Node | Index | enp2s0 IPv4 | enp2s0 IPv6 | Bridge br0/br-ex IPv4 | Bridge br0/br-ex IPv6 |
|---|---|---|---|---|---|
| master-0 (RR) | 2 | 192.168.111.80 | fd2e:6f44:5dd8:c956::50 | 192.168.110.2 | fd00:110::2 |
| master-1 (RR) | 3 | 192.168.111.81 | fd2e:6f44:5dd8:c956::51 | 192.168.110.3 | fd00:110::3 |
| master-2 (RR) | 4 | 192.168.111.82 | fd2e:6f44:5dd8:c956::52 | 192.168.110.4 | fd00:110::4 |
| worker-0 | 5 | 192.168.111.83 | fd2e:6f44:5dd8:c956::53 | 192.168.110.5 | fd00:110::5 |
| worker-1 | 6 | 192.168.111.84 | fd2e:6f44:5dd8:c956::54 | 192.168.110.6 | fd00:110::6 |

The TOR has the following addressing scheme.

| Node | enp2s0 IPv4 | enp2s0 IPv6 |
|---|---|---|
| TOR (sno-labbm) | 192.168.111.1 | fd2e:6f44:5dd8:c956::1 |

### Address derivation formula

Given node index `N` (e.g. `2`, `3`, `4`, `5`, `6`):

| Address | Formula |
|---|---|
| Bridge IPv4 | `192.168.110.{N}` |
| Bridge IPv6 | `fd00:110::{N}` |
| Loopback IPv6 | `fd00::{N}` |
| SRv6 Locator | `fd00:2:{N}::/48` |
| ISIS NET | `49.0001.0000.0000.{N}.00` |

### Controller-derived addressing (from underlay resource)

The OpenPERouter controller derives per-node router ID, loopback, and SRv6 locator from these ranges:

| Parameter | Range | Description |
|---|---|---|
| `routerIDCIDR` | `10.0.0.0/24` | Per-node router ID |
| `tunnelEndpoint.cidrs` | `fd00::/64` | Per-node loopback IPv6 (VTEP source) |
| `srv6.locator.basePrefix` | `fd00:2::/48` | SRv6 locator base (uSID f3216) |

Concrete per-node values:

| Node | Router ID | Tunnel Endpoint | SRv6 Locator |
|---|---|---|---|
| master-0 | 10.0.0.2 | fd00::2 | fd00:2:2::/48 |
| master-1 | 10.0.0.3 | fd00::3 | fd00:2:3::/48 |
| master-2 | 10.0.0.4 | fd00::4 | fd00:2:4::/48 |
| worker-0 | 10.0.0.5 | fd00::5 | fd00:2:5::/48 |
| worker-1 | 10.0.0.6 | fd00::6 | fd00:2:6::/48 |

### TOR addressing (external, manually configured)

| Parameter | Value |
|---|---|
| Router ID | 10.0.0.20 |
| Loopback IPv6 | fc00:0:20::1 |
| SRv6 prefix | fd00:20::/48 |
| uN (node SID) | fd00:20:: |
| uDT46 (VRF decap) | fd00:20:0:1:: |
| VRF red: lored | 10.10.20.1/32 |
| VRF red: lo-extra | 10.100.0.1/32 (DNS + NTP) |

## BGP Peering (AS 65500, all iBGP)

### L3VPN sessions (ipv4 vpn + ipv6 vpn)

Cluster nodes peer with the TOR at `fc00:0:20::1` for north-south L3VPN over SRv6,
using `update-source fd00::{N}` (tunnel endpoint) and `capability extended-nexthop`.
The TOR peers back to each node at `fd00::{N}`.

| From | To | AFIs |
|---|---|---|
| each node | TOR (fc00:0:20::1) | ipv4 vpn, ipv6 vpn |
| TOR | fd00::{N} per node | ipv4 vpn, ipv6 vpn |

### EVPN sessions (l2vpn evpn)

All 3 masters are EVPN route reflectors. EVPN peers over the directly connected
`enp2s0` IPv6 addresses (`fd2e:6f44:5dd8:c956::/120`), not over loopback.
The TOR does not participate in EVPN.

**Masters** (each master runs this config):
- `listenRange: fd2e:6f44:5dd8:c956::/120` — accepts RR clients (workers) with `routeReflectorClient`
- Explicit peers with `::50`, `::51`, `::52` — RR-to-RR mesh (plain iBGP, no route-reflector-client)

**Workers** (each worker runs this config):
- Explicit peers with `::50`, `::51`, `::52` — all 3 masters

| From | To | Role |
|---|---|---|
| master (RR) | listenRange fd2e:6f44:5dd8:c956::/120 | route-reflector-client |
| master (RR) | master-0 (::50) | RR-to-RR iBGP |
| master (RR) | master-1 (::51) | RR-to-RR iBGP |
| master (RR) | master-2 (::52) | RR-to-RR iBGP |
| worker | master-0 (::50) | client (via listenRange) |
| worker | master-1 (::51) | client (via listenRange) |
| worker | master-2 (::52) | client (via listenRange) |

## SRv6

Locator format: uSID f3216 (block `32 bits`, node `16 bits`, function `16 bits`).
Encapsulation behavior: `H.Encaps.Red`.

Per-node SRv6 SIDs are derived by the controller from `basePrefix: fd00:2::/48`.

**TOR SIDs** (manually configured):

| SID | Value |
|---|---|
| uN (node SID) | fd00:20:: |
| uDT46 (VRF decap) | fd00:20:0:1:: |

## L3VPN Routes (VRF red)

### What each cluster node sees

| Prefix | Source | Via |
|---|---|---|
| 10.10.20.1/32 | TOR VRF loopback (lored) | SRv6 (fd00:20:0:1::) |
| 10.100.0.1/32 | TOR DNS/NTP loopback (lo-extra) | SRv6 (fd00:20:0:1::) |
| 192.168.110.0/24 | Local br-pe-210 (L2 gateway) | Connected |

### What the TOR sees

| Prefix | Source | Via |
|---|---|---|
| 192.168.110.{2-6}/32 | Cluster node bridge IPs | SRv6 (per-node uDT46) |
| 10.10.20.1/32 | Local lored | Connected |
| 10.100.0.1/32 | Local lo-extra | Connected |

## L2VPN / EVPN (VNI 210)

All cluster nodes (masters and workers) share an L2 segment via VXLAN bridge `br-pe-210`:
- Gateway IP: `192.168.110.1/24` + `fd00:110::1/64` (anycast on all nodes)
- VNI: 210
- RT: 65500:210

EVPN type-2 (MAC/IP) and type-3 (BUM/VTEP) routes are exchanged between
all cluster nodes via all 3 masters as route reflectors. The TOR does **not**
participate in EVPN L2 — north-south traffic only via L3VPN.

## Services on TOR (VRF red)

### DNS (dnsmasq on 10.100.0.1)

| Record | Target |
|---|---|
| api.sno-lab.example.com | 192.168.110.10 (API VIP) |
| api-int.sno-lab.example.com | 192.168.110.10 (API VIP) |
| *.apps.sno-lab.example.com | 192.168.110.11 (Ingress VIP) |

### NTP (chronyd on 10.100.0.1)

Stratum 3 orphan server. All cluster nodes sync to it via the SRv6 L3VPN path.

## ISIS Underlay

- Area: `49.0001`
- Level: L1 only
- IPv6-only: only `ipv6 router isis` on interfaces (no IPv4 ISIS)
- Interface: `enp2s0` on cluster nodes, dedicated interface on TOR
- IPv4 subnet: `192.168.111.0/24`
- IPv6 subnet: `fd2e:6f44:5dd8:c956::/120`
- All nodes form L1 adjacencies on the shared broadcast segment
