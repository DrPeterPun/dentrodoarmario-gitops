#!/usr/bin/env bash
# Create (or update) the second-star-production secret from a dotenv file.
# The file is not committed. Run this on a machine that can reach the cluster,
# after merlin/.env exists:
#
#   apps/second-star/scripts/create-secret.sh /path/to/Second-Star/merlin/.env
#
# Optional, for private GHCR images:
#   GHCR_USER=... GHCR_TOKEN=... apps/second-star/scripts/create-secret.sh /path/to/.env
set -euo pipefail

ENV_FILE="${1:-}"
if [[ -z "${ENV_FILE}" || ! -f "${ENV_FILE}" ]]; then
  echo "usage: $0 /path/to/merlin/.env" >&2
  exit 1
fi

NS=second-star-production
TMP_ENV="$(mktemp)"
trap 'rm -f "$TMP_ENV"' EXIT

python3 - "$ENV_FILE" "$TMP_ENV" <<'PY'
import sys
from urllib.parse import unquote, urlparse

src, dest = sys.argv[1], sys.argv[2]

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

def with_schema(url):
    base, query = (url.split("?", 1) + [""])[:2]
    if "schema=" in query:
        return url
    joiner = "&" if query else "?"
    return f"{base}{('?' + query) if query else ''}{joiner}schema=scrooge"

def rewrite_localhost(url):
    host = urlparse(url).hostname or ""
    if host not in ("localhost", "127.0.0.1"):
        return url, False
    needle = f"@{host}"
    if needle in url:
        return url.replace(needle, "@db", 1), True
    prefix = f"://{host}"
    if prefix in url:
        return url.replace(prefix, "://db", 1), True
    return url, False

data = parse_env(src)
required = ["DATABASE_URL", "JWT_SECRET", "DISCORD_CLIENT_ID", "DISCORD_CLIENT_SECRET"]
missing = [key for key in required if not data.get(key)]
if missing:
    sys.exit("missing in env file: " + ", ".join(missing))

rewritten, did_rewrite = rewrite_localhost(data["DATABASE_URL"])
data["DATABASE_URL"] = with_schema(rewritten)

parsed = urlparse(data["DATABASE_URL"])
db_name = (parsed.path or "").lstrip("/").split("/")[0]
data.setdefault("POSTGRES_USER", unquote(parsed.username or ""))
data.setdefault("POSTGRES_PASSWORD", unquote(parsed.password or ""))
data.setdefault("POSTGRES_DB", db_name)
data.setdefault("API_PUBLIC_URL", "http://192.168.1.101:3010")
data.setdefault("FRONTEND_URL", "http://192.168.1.101:8088")
data.setdefault(
    "DISCORD_REDIRECT_URI",
    data["API_PUBLIC_URL"].rstrip("/") + "/auth/discord/callback",
)
data.setdefault("COOKIE_SECURE", "false")
data.setdefault("NODE_ENV", "production")
data.setdefault("PORT", "3000")
data.setdefault("PRISMA_DB_PUSH", "false")

for key in ("POSTGRES_USER", "POSTGRES_PASSWORD", "POSTGRES_DB"):
    if not data.get(key):
        sys.exit(f"could not derive {key} from DATABASE_URL; set it in the env file")

with open(dest, "w", encoding="utf-8") as handle:
    for key in sorted(data):
        handle.write(f"{key}={data[key]}\n")

print("rewrote DATABASE_URL host localhost -> db" if did_rewrite else "kept DATABASE_URL host")
print("secret keys:", ", ".join(sorted(data)))
PY

kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic second-star-env \
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
