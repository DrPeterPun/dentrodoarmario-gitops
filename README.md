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
```

ApplicationSet creates one Application per overlay:

| Overlay | Argo CD app | Namespace |
|---|---|---|
| `apps/batalha-naval/overlays/production` | `batalha-naval-production` | `batalha-naval-production` |
| `apps/disney-bros/overlays/production` | `disney-bros-production` | `disney-bros-production` |
| `apps/mtgo/overlays/production` | `mtgo-production` | `mtgo-production` |

There is no staging overlay. Each world is bound to a host path on node `dentrodoarmario` (`/home/serverino/mc_batalhanaval` and `/home/serverino/mc_disneybros`). A second environment would need different disks and a different LAN port/IP.

Batalha Naval is exposed on LAN `192.168.1.101:25566` (container still listens on `25565`). Disney Bros is `192.168.1.101:25565`.

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
- app `mtgo`, environment `production`, image `local/mtgosdk` (bot) or `local/meta-stats` (web + scheduler)

Application repos can also fire `repository_dispatch` type `update-image` with `app`, `environment`, `image`, and `tag`. That is how mtgo-bot / meta-stats CI should roll a new build into this cluster.

## Validate locally

```bash
kubectl kustomize apps/batalha-naval/overlays/production
kubectl kustomize apps/disney-bros/overlays/production
kubectl kustomize apps/mtgo/overlays/production
```

## MTGO stack

Four compose services from `mtgo-bot/docker-compose.yml`, one Argo CD app so they share namespace `mtgo-production` and the hostname `db`. Images stay `local/*` (they are built on the node, not published).

| Deploy | Image | Role |
|---|---|---|
| `mtgo-db` | `postgres:16` | Postgres; `schema.sql` is mounted into `docker-entrypoint-initdb.d` for first boot |
| `mtgo-bot` | `local/mtgosdk:headless` | `wine-run src/MTGOBot.csproj` under Wine/Xvfb |
| `mtgo-web` | `local/meta-stats:latest` | `uv run uvicorn app.web.main:app` on LAN `192.168.1.101:8000` |
| `mtgo-scheduler` | `local/meta-stats:latest` | `uv run python -m app.scheduler.main` |

Create these host paths on `dentrodoarmario` before the first sync:

- `/home/serverino/mtgo-postgres` — Postgres data
- `/home/serverino/mtgo-bot` — checkout of `mtgo-bot` (mounted at `/workspace`)
- `/home/serverino/mtgo-sdk` — `MTGOSDK` drop folder (mounted at `/MTGOSDK`)
- `/home/serverino/mtgo-wine` — Wine prefix

Build and load `local/mtgosdk:headless` (from `mtgo-docker`) and `local/meta-stats:latest` (from `meta-stats/Dockerfile`) onto that node. Then create the Secret from `mtgo-bot/src/.env` — do not commit it. The file uses `PGUSER` / `PGPASSWORD` / `PGDATABASE`; the Secret also needs `DATABASE_URL` and a `dotenv` copy of the file for `DotEnv.LoadFile()`:

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
