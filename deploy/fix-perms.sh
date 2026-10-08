#!/usr/bin/env bash
# Fix ownership + world-traverse so:
#   - user PROJECT_OWNER (default: goum) can edit the tree
#   - the site container behind Apache can read bind-mounted www/
#
# Prod path: browser → Apache → 127.0.0.1:HTTP_PORT (Docker).
# Typical 403: project under /home/goum with mode 750 → container cannot traverse home.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT/.env}"

env_get() {
  local key="$1" default="${2:-}"
  local value=""
  if [[ -f "$ENV_FILE" ]]; then
    value="$(grep -E "^${key}=" "$ENV_FILE" | tail -n1 | cut -d= -f2- | tr -d '\r' || true)"
  fi
  if [[ -z "$value" ]]; then
    value="$default"
  fi
  printf '%s' "$value"
}

OWNER="$(env_get PROJECT_OWNER "")"
if [[ -z "$OWNER" ]]; then
  if id -u goum >/dev/null 2>&1; then
    OWNER="goum"
  else
    OWNER="$(stat -c '%U' "$ROOT" 2>/dev/null || echo "")"
  fi
fi
if [[ -z "$OWNER" ]] || ! id -u "$OWNER" >/dev/null 2>&1; then
  echo "PROJECT_OWNER '${OWNER}' is not a valid user. Set PROJECT_OWNER in .env." >&2
  exit 1
fi
GROUP="$(id -gn "$OWNER")"

need_root=0
if [[ "$(stat -c '%U' "$ROOT")" != "$OWNER" ]]; then
  need_root=1
fi
# Parent dirs must be traversable by "other" (Docker nginx ≠ host user).
path="$ROOT"
while [[ "$path" != "/" ]]; do
  mode="$(stat -c '%a' "$path" 2>/dev/null || echo "")"
  if [[ -n "$mode" ]]; then
    other="$((10#${mode: -1}))"
    if (( (other & 1) == 0 )); then
      need_root=1
      break
    fi
  fi
  path="$(dirname "$path")"
done

if [[ "$(id -u)" -ne 0 && "$need_root" -eq 1 ]]; then
  exec sudo ENV_FILE="$ENV_FILE" "$0" "$@"
fi

echo "Perms: owner=${OWNER}:${GROUP}  root=${ROOT}"

# Keep the tree editable by the project user (deploy via ubuntu/sudo often leaves root-owned bits).
if [[ "$(id -u)" -eq 0 ]]; then
  chown -R "${OWNER}:${GROUP}" "$ROOT"
fi

# nginx (container) must read content; execute-bit on dirs for traversal.
chmod -R a+rX \
  "$ROOT/www" \
  "$ROOT/docker" \
  "$ROOT/api" \
  "$ROOT/deploy" 2>/dev/null || true

# Ensure key files stay readable even if umask was tight.
for f in "$ROOT/www/index.html" "$ROOT/www/robots.txt" "$ROOT/www/sitemap.xml" \
         "$ROOT/docker-compose.yml" "$ROOT/Dockerfile" "$ROOT/.env"; do
  [[ -e "$f" ]] && chmod a+r "$f" || true
done
# .env readable by owner/group only (may contain contact mail).
[[ -f "$ROOT/.env" ]] && chmod 640 "$ROOT/.env" || true
if [[ "$(id -u)" -eq 0 && -f "$ROOT/.env" ]]; then
  chown "${OWNER}:${GROUP}" "$ROOT/.env"
fi

# o+x on every parent so non-owner (container uid) can walk into the bind mount.
# Does NOT grant list (r) on home — only traverse (x).
if [[ "$(id -u)" -eq 0 ]]; then
  path="$ROOT"
  while [[ "$path" != "/" ]]; do
    chmod o+x "$path"
    path="$(dirname "$path")"
  done
fi

echo "OK — www is world-readable; parents are traversable (o+x); owned by ${OWNER}."
echo "If the site still 403s: make doctor"
