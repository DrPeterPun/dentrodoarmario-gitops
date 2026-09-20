# WireGuard

In-cluster WireGuard server so clients can reach LAN services on node `dentrodoarmario` (`192.168.1.101`) — Minecraft, MTGO web, and anything else bound to that LAN.

Argo CD deploys this overlay as Application `wireguard-production` in namespace `wireguard-production`.

| | |
|---|---|
| UDP listen (LAN) | `192.168.1.101:51820` |
| UDP WAN (clients) | public IP port **41820** (router maps 41820 → 51820) |
| Tunnel subnet | `10.13.13.0/24` |
| Split tunnel | `10.13.13.0/24` and `192.168.1.0/24` (not all Internet traffic) |
| Seeded peers | `laptop`, `phone` |
| Config on disk | `/home/serverino/wireguard` (create this directory before the first sync) |

Keys and peer configs are generated on first start and stored on the local PV. They are **not** committed to Git.

## Before the first sync

On node `dentrodoarmario`:

```bash
sudo mkdir -p /home/serverino/wireguard
sudo chown 1000:1000 /home/serverino/wireguard
```

If clients will connect from the Internet, on the MEO GR141IG forward **UDP 41820 → 192.168.1.101:51820**. That router rejects UDP *external* ports above 49999, so the WAN port cannot be 51820; the process still listens on 51820 on the node. If `SERVERURL=auto` picks the wrong Endpoint (CGNAT, etc.), set it in `apps/wireguard/base/deployment.yaml` to a DDNS name or your public IP, merge, and let Argo CD roll the pod (existing peer keys are kept; only confs regenerate).

## Fetch a client config

After the pod is Ready:

```bash
kubectl -n wireguard-production rollout status deploy/wireguard
kubectl -n wireguard-production exec deploy/wireguard -- wg show

# text config (import this file in the WireGuard app)
kubectl -n wireguard-production exec deploy/wireguard -- \
  cat /config/peer_laptop/peer_laptop.conf

kubectl -n wireguard-production exec deploy/wireguard -- \
  cat /config/peer_phone/peer_phone.conf

# QR code in the terminal (phones)
kubectl -n wireguard-production exec deploy/wireguard -- /app/show-peer laptop
kubectl -n wireguard-production exec deploy/wireguard -- /app/show-peer phone
```

Treat those files as secrets. Do not commit them.

## Connect

1. Install [WireGuard](https://www.wireguard.com/install/) (Windows / macOS / Linux / iOS / Android).
2. Import `peer_laptop.conf` or `peer_phone.conf` (or scan the QR code).
3. Off-LAN Endpoint should be `YOUR_PUBLIC_DNS_OR_IP:41820` (already set in generated confs). On-LAN you can use `192.168.1.101:51820`.
4. Activate the tunnel.

You should then reach:

| Service | Address |
|---|---|
| Disney Bros Minecraft | `192.168.1.101:25565` |
| Batalha Naval Minecraft | `192.168.1.101:25566` |
| MTGO web | `http://192.168.1.101:8000` |

`ping 192.168.1.101` is a quick tunnel check. Handshake time from `wg show` should be recent.

## Add another peer

Set `PEERS` to a longer comma-separated list of alphanumeric names (for example `laptop,phone,tablet`), merge, and restart the pod. New peer folders appear under `/config/peer_<name>/`. Do not rename existing peer names if you want to keep their keys.
