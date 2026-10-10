# Dentro do Armário — GitOps

Argo CD deploys what is in this repository. The two Minecraft servers use the public `itzg/minecraft-server` image, so their full deploy config lives here. There is no application-repo CI for them: change YAML in Git, Argo CD syncs the cluster.

```
bootstrap/                 # one-time Argo CD install
clusters/in-cluster/       # AppProject, ApplicationSet, local-storage StorageClass
apps/batalha-naval/
  base/                    # Deployment, Service, PV, PVC
  overlays/production/
apps/disney-bros/
  base/
  overlays/production/
apps/mtgo/
  base/                    # db, bot, web, scheduler
  overlays/production/
apps/second-star/
  base/                    # postgres, merlin API, encanto web
  overlays/production/
apps/mc-router/
  base/                    # Minecraft hostname router on 25565
  overlays/production/
apps/wireguard/
  base/                    # UDP 41820 VPN gateway
  overlays/production/
```

ApplicationSet creates one Application per overlay:

| Overlay | Argo CD app | Namespace |
|---|---|---|
| `apps/batalha-naval/overlays/production` | `batalha-naval-production` | `batalha-naval-production` |
| `apps/disney-bros/overlays/production` | `disney-bros-production` | `disney-bros-production` |
| `apps/mtgo/overlays/production` | `mtgo-production` | `mtgo-production` |
| `apps/second-star/overlays/production` | `second-star-production` | `second-star-production` |
| `apps/mc-router/overlays/production` | `mc-router-production` | `mc-router-production` |
| `apps/wireguard/overlays/production` | `wireguard-production` | `wireguard-production` |

There is no staging overlay. Each world is bound to a host path on node `dentrodoarmario` (`/home/serverino/mc_batalhanaval` and `/home/serverino/mc_disneybros`). A second environment would need different disks and a different LAN port/IP.

k3s already runs Traefik on `192.168.1.101:80` and `:443`. The Second Star Ingress is the only public website: `disneybros.pt` goes to Encanto and `api.disneybros.pt` goes to Merlin. Any other hostname on those ports gets Traefik's 404. The web and API still listen on the LAN at `192.168.1.101:8088` and `:3010`.

MTGO web stays LAN-only at `192.168.1.101:8000`. It has no Ingress.

mc-router owns `192.168.1.101:25565`. `minecraft.pbpereira.pt` and `192.168.1.101` reach Disney Bros. Any other address, including the public IP, is refused. Batalha Naval stays on LAN `192.168.1.101:25566` (container still listens on `25565`). WireGuard listens on `192.168.1.101:41820/udp` (`minecraft.pbpereira.pt:41820` from the Internet). See [apps/wireguard/README.md](apps/wireguard/README.md).

On the router, forward TCP 80, TCP 443, and TCP 25565 to `192.168.1.101`, and keep UDP 41820. Do not forward 8000, 8088, 3010, or 25566; those are the in-network ports. `disneybros.pt` and `api.disneybros.pt` both need DNS to the same address. The site and API cannot share one hostname: Encanto's pages (`/movies`, `/books`, and the rest) use the same paths as Merlin.

## Bootstrap

Use server-side apply for the Argo CD install. The ApplicationSet CRD is larger than
kubectl's client-side `last-applied-configuration` annotation limit (256KiB), so a
plain `kubectl apply -k` can leave Argo CD running without `applicationsets.argoproj.io`.

```bash
kubectl apply --server-side -k bootstrap/argo-cd
kubectl wait --for=condition=Available -n argocd deployment/argocd-server --timeout=180s
kubectl wait --for=condition=Available -n argocd deployment/argocd-applicationset-controller --timeout=180s
kubectl apply -f bootstrap/root-app.yaml
```

If these workloads already run in another namespace (for example `default`), the existing PVCs stay bound to the old namespace. Move or recreate the claim in the new namespace, or keep the old objects and let Argo CD adopt them after you annotate them.

## Change what is running

Edit the overlay (or base env values) and merge. Typical changes:

- Image tag in `overlays/production/kustomization.yaml` (`itzg/minecraft-server`)
- Fabric `VERSION`, `MEMORY`, or `MOTD` in `base/deployment.yaml`

Or run **Actions → Update image tag** with:

- app `batalha-naval` or `disney-bros`, environment `production`, image `itzg/minecraft-server`, and a tag such as `java21`
- app `mtgo`, environment `production`, image `local/mtgosdk` (bot) or `local/meta-stats` (web + scheduler), optional `newName` such as `videreproject/mtgosdk` or `ghcr.io/mtgometastats/meta-stats`

Application repos fire `repository_dispatch` type `update-image` with `app`, `environment`, `image`, `tag`, and optional `newName`. A `client_payload.images` array updates several images in one commit. Set a `GITOPS_TOKEN` secret in those repos (a PAT that can dispatch this repository) so a commit rebuilds the image and rolls the overlay.

## Validate locally

```bash
kubectl kustomize apps/batalha-naval/overlays/production
kubectl kustomize apps/disney-bros/overlays/production
kubectl kustomize apps/mtgo/overlays/production
kubectl kustomize apps/wireguard/overlays/production
kubectl kustomize apps/second-star/overlays/production
kubectl kustomize apps/mc-router/overlays/production
```

## MTGO stack

Four compose services from `mtgo-bot/docker-compose.yml`, one Argo CD app so they share namespace `mtgo-production` and the hostname `db`.

The bot used to reference `local/mtgosdk:headless` because an older .NET 10 preview SDK was not in the public image. Upstream `videreproject/mtgosdk:headless` now ships a released .NET 10 SDK, so Kubernetes can pull it. `meta-stats` and a baked `mtgo-bot` image are published to GHCR by app-repo CI.

| Deploy | Image | Role |
|---|---|---|
| `mtgo-db` | `postgres:16` | Postgres; `schema.sql` is mounted into `docker-entrypoint-initdb.d` for first boot |
| `mtgo-bot` | `videreproject/mtgosdk:headless` (until mtgo-bot CI publishes `ghcr.io/mtgometastats/mtgo-bot`) | `wine-run src/MTGOBot.csproj` under Wine/Xvfb |
| `mtgo-web` | `ghcr.io/mtgometastats/meta-stats:latest` | `uv run uvicorn app.web.main:app` on LAN `192.168.1.101:8000` |
| `mtgo-scheduler` | `ghcr.io/mtgometastats/meta-stats:latest` | `uv run python -m app.scheduler.main` |

Create these host paths on `dentrodoarmario` before the first sync:

- `/home/serverino/wireguard` — WireGuard keys and peer configs (`chown 1000:1000`)
- `/home/serverino/mtgo-postgres` — Postgres data
- `/home/serverino/mtgo-bot` — checkout of `mtgo-bot` (mounted at `/workspace`)
- `/home/serverino/mtgo-sdk` — `MTGOSDK` drop folder (mounted at `/MTGOSDK`)
- `/home/serverino/mtgo-wine` — Wine prefix

An init container fetches `MTGOSDK` NuGet packages onto `/home/serverino/mtgo-sdk`, and another seeds `C:\dotnet` into the Wine prefix if that volume is empty.

Then create the Secret from `mtgo-bot/src/.env` — do not commit it. The file uses `PGUSER` / `PGPASSWORD` / `PGDATABASE`; the Secret also needs `DATABASE_URL` and a `dotenv` copy of the file for `DotEnv.LoadFile()`:

```bash
ENV_FILE=/path/to/mtgo-bot/src/.env
set -a && . "$ENV_FILE" && set +a
kubectl create namespace mtgo-production --dry-run=client -o yaml | kubectl apply -f -
TMP_ENV=$(mktemp)
cp "$ENV_FILE" "$TMP_ENV"
printf 'DATABASE_URL=postgresql+psycopg://%s:%s@db:5432/%s\n' "$PGUSER" "$PGPASSWORD" "$PGDATABASE" >> "$TMP_ENV"
kubectl create secret generic mtgo-env --namespace mtgo-production --from-env-file "$TMP_ENV"
kubectl create secret generic mtgo-dotenv --namespace mtgo-production --from-file "dotenv=${ENV_FILE}"
rm -f "$TMP_ENV"
```

## Second Star

Merlin (API), Encanto (web), and Postgres. Images are built by `MFJess/Second-Star` and published as `ghcr.io/mfjess/second-star-merlin` and `ghcr.io/mfjess/second-star-encanto`. ApplicationSet creates `second-star-production`.

Create this host path on `dentrodoarmario` before the first sync, owned by the Postgres user in the image:

```bash
sudo mkdir -p /home/serverino/second-star-postgres
sudo chown 999:999 /home/serverino/second-star-postgres
```

The app secret is not in git. When `merlin/.env` exists, create it from a machine that can reach the API server. The script keeps every key in that file, rewrites a `localhost` database host to the in-cluster service `db`, and fills deploy defaults that are missing (`API_PUBLIC_URL`, `FRONTEND_URL`, `DISCORD_REDIRECT_URI`, `COOKIE_SECURE=false`, `PRISMA_DB_PUSH=false`).

```bash
apps/second-star/scripts/create-secret.sh /path/to/Second-Star/merlin/.env
```

Private GHCR pulls also need `ghcr-pull` in the same namespace. Pass `GHCR_USER` and `GHCR_TOKEN` when running the script, or create the docker-registry secret yourself.

Defaults, unless `.env` already sets them:

| Key | Value |
|---|---|
| `FRONTEND_URL` | `http://disneybros.pt` |
| `API_PUBLIC_URL` | `http://api.disneybros.pt` |
| `DISCORD_REDIRECT_URI` | `http://api.disneybros.pt/auth/discord/callback` |
| `DATABASE_URL` host | `db:5432`, schema `scrooge` |

`PRISMA_DB_PUSH=true` makes Merlin run `prisma db push` on startup. Use that once for an empty in-cluster database, then set it back to `false`. Leave it `false` when `DATABASE_URL` points at a database that already has data.

The running secret is not updated by a git merge. If `merlin/.env` still has the LAN URLs, change `FRONTEND_URL`, `API_PUBLIC_URL`, and `DISCORD_REDIRECT_URI` there and run the script again, then restart the web and API pods so Encanto rewrites `config.js`. Keys already present in the env file are kept.

Discord only accepts `http://localhost` redirect URIs without HTTPS. `http://api.disneybros.pt/auth/discord/callback` has to be replaced with an HTTPS URL in `.env` and in the Discord application before login works from the public site.
