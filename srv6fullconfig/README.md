# OpenPERouter — Rawconfig Deployment

A rawconfig deployment of OpenPERouter on an OpenShift cluster. No controller
manages FRR — systemd services derive addressing at boot, render FRR config
from templates, and build the VRF/VXLAN/bridge infrastructure.

## Architecture

```
              ┌─────────┐
              │   TOR   │
              └────┬────┘
                   │  ISIS + SRv6 (L3VPN)
        ┌──────────┼──────────┐
        │          │          │
   ┌────┴───┐ ┌───┴────┐ ┌───┴────┐
   │master-0│ │master-1│ │worker-0│  ...
   │  (RR)  │ │        │ │        │
   └────────┘ └────────┘ └────────┘
        ◄── EVPN / VXLAN (L2VPN) ──►
            reflected by master-0
```

- **North-south** (nodes ↔ TOR): L3VPN over SRv6 (ISIS underlay)
- **East-west** (node ↔ node): EVPN with VXLAN, master-0 as route reflector
- The TOR does **not** participate in EVPN

See [TOPOLOGY.md](TOPOLOGY.md) for full addressing and peering details.

## Host Configuration

The systemd services in [`extras/rawconfig/`](extras/rawconfig/) run in
sequence at boot to configure each node:

| Script | What it does |
|--------|-------------|
| `setup-underlay.sh` | Waits for FRR and br0, derives the node index (last octet) and loopback IPv6 from the br0 IP |
| `generate-config.sh` | Picks the master or worker config based on node index, renders rawfrrconfigs template with `envsubst` |
| `openperouter-common.sh` | Shared helpers (logging, namespace utilities) sourced by all scripts |

## FRR Configuration

FRR config is rendered from templates in `extras/rawconfig/`:

- **`openpe_master_raw.yaml.template`** - holds optional raw configuration for the masters
- **`openpe_worker_raw.yaml.template`** - holds optional raw configuration for the workers
- **`openpe_master.yaml`** - holds the OpenPERouter static configuration for the masters
- **`openpe_worker.yaml`** - holds the OpenPERouter static configuration for the workers

`generate-config.sh` selects master or worker configs by comparing the node's
last octet against `RR_NODE_IDX_0/1/2`, copies the static YAML files, renders
the `_raw.yaml.template` via `envsubst`, and writes the result for FRR to apply.

## Configuration (vpn-setup.env)

All tunable parameters live in [`extras/rawconfig/vpn-setup.env`](extras/rawconfig/vpn-setup.env):

| Variable | Default | Description |
|----------|---------|-------------|
| `FRR_READY_TIMEOUT` | `60` | Seconds to wait for the FRR container to start |
| `BR0_READY_TIMEOUT` | `120` | Seconds to wait for br0/br-ex to get an IP |

## Building

- **Appliance ISO**: [`appliance/generate_appliance.sh`](appliance/generate_appliance.sh) `<pull_secret_file>`
- **Config-image ISO**: [`configimage/generate_config_image.sh`](configimage/generate_config_image.sh) `<pull_secret_file>`
