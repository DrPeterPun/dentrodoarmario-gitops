#!/usr/bin/env bash
# Create (or update) the mickey2-production secret from a dotenv file.
# The file is not committed. Run this on a machine that can reach the cluster,
# after Mickey2/.env exists:
#
#   apps/mickey2/scripts/create-secret.sh /path/to/Mickey2/.env
#
# Optional, for private GHCR images:
#   GHCR_USER=... GHCR_TOKEN=... apps/mickey2/scripts/create-secret.sh /path/to/.env
set -euo pipefail

ENV_FILE="${1:-}"
if [[ -z "${ENV_FILE}" || ! -f "${ENV_FILE}" ]]; then
  echo "usage: $0 /path/to/Mickey2/.env" >&2
  exit 1
fi

NS=mickey2-production
TMP_ENV="$(mktemp)"
trap 'rm -f "$TMP_ENV"' EXIT

python3 - "$ENV_FILE" "$TMP_ENV" <<'PY'
import sys

src, dest = sys.argv[1], sys.argv[2]
CLUSTER_MERLIN = "http://second-star-api.second-star-production.svc.cluster.local:3010"
# The bot calls Merlin paths at the root (/users, /hogwarts, ...). The public
# site prefixes those with /api and Encanto strips it. Inside the cluster the
# Service is already the API, so those URLs are rewritten to the Service.
STALE_MERLIN = {
    "",
    "http://localhost:3000",
    "http://127.0.0.1:3000",
    "http://localhost:3010",
    "http://127.0.0.1:3010",
    "http://192.168.1.101:3010",
    "http://secondstar.pt",
    "https://secondstar.pt",
    "http://secondstar.pt/api",
    "https://secondstar.pt/api",
}

def parse_env(path):
    data = {}
    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[len("export "):]
            if "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
                value = value[1:-1]
            data[key] = value
    return data

data = parse_env(src)
if not data.get("DISCORD_TOKEN"):
    sys.exit("missing in env file: DISCORD_TOKEN")

merlin = data.get("MERLIN_URL", "").rstrip("/")
if merlin in STALE_MERLIN:
    data["MERLIN_URL"] = CLUSTER_MERLIN
    print("rewrote MERLIN_URL -> in-cluster second-star-api")
else:
    data["MERLIN_URL"] = merlin
    print("kept MERLIN_URL")

kept = {key: data[key] for key in ("DISCORD_TOKEN", "MERLIN_URL", "EXCEL_MARATONA", "MINECRAFT_IP") if data.get(key)}
with open(dest, "w", encoding="utf-8") as handle:
    for key in ("DISCORD_TOKEN", "MERLIN_URL", "EXCEL_MARATONA", "MINECRAFT_IP"):
        if key in kept:
            handle.write(f"{key}={kept[key]}\n")

print("secret keys:", ", ".join(key for key in ("DISCORD_TOKEN", "MERLIN_URL", "EXCEL_MARATONA", "MINECRAFT_IP") if key in kept))
PY

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic mickey2-env \
  --namespace "$NS" \
  --from-env-file "$TMP_ENV" \
  --dry-run=client -o yaml | kubectl apply -f -

if [[ -n "${GHCR_USER:-}" && -n "${GHCR_TOKEN:-}" ]]; then
  kubectl create secret docker-registry ghcr-pull \
    --namespace "$NS" \
    --docker-server=ghcr.io \
    --docker-username="$GHCR_USER" \
    --docker-password="$GHCR_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "updated ghcr-pull"
else
  echo "ghcr-pull was not changed. Set GHCR_USER and GHCR_TOKEN to create it."
fi
