#!/usr/bin/env bash
# Install / refresh the Goum host Apache reverse-proxy vhost (Ubuntu Apache 2.4).
# Intended for Ubuntu 24.04 / 26.04 with apache2 from apt.
#
# Safety: only writes sites-available/<domain>.conf (+ optional <domain>-le-ssl.conf
# port fix). Does not disable or rewrite other sites' vhosts.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT/.env}"
TEMPLATE="$ROOT/deploy/apache-host-vhost.conf"
HTTP2_CONF="$ROOT/deploy/apache-http2.conf"
PROXY_TLS_CONF="$ROOT/deploy/apache-proxy-tls.conf"
SITE_AVAILABLE="/etc/apache2/sites-available"
SITE_ENABLED="/etc/apache2/sites-enabled"
CONF_AVAILABLE="/etc/apache2/conf-available"
PROXY_TLS_NAME="goum-proxy-tls"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root (make deploy uses sudo)." >&2
  exit 1
fi

if [[ ! -f "$TEMPLATE" ]]; then
  echo "Missing template: $TEMPLATE" >&2
  exit 1
fi

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

HTTP_PORT="$(env_get HTTP_PORT 8090)"
SITE_URL="$(env_get SITE_URL "")"
DOMAIN_RAW="$(env_get DOMAIN "")"
if [[ -z "$DOMAIN_RAW" ]]; then
  DOMAIN_RAW="$(env_get DEPLOY_DOMAIN "")"
fi
CERT_EMAIL="$(env_get CONTACT_MAIL "")"
if [[ -z "$CERT_EMAIL" ]]; then
  CERT_EMAIL="$(env_get CERTBOT_EMAIL "")"
fi

if [[ -z "$DOMAIN_RAW" && -n "$SITE_URL" ]]; then
  DOMAIN_RAW="$(printf '%s' "$SITE_URL" | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://##' | cut -d/ -f1 | cut -d: -f1)"
fi
if [[ -z "$DOMAIN_RAW" ]]; then
  DOMAIN_RAW="goum.eu"
fi
DOMAIN="$(printf '%s' "$DOMAIN_RAW" | tr '[:upper:]' '[:lower:]')"
DOMAIN="${DOMAIN#www.}"
if [[ -z "$SITE_URL" ]]; then
  SITE_URL="https://${DOMAIN}"
fi

if [[ ! "$DOMAIN" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]]; then
  echo "Invalid DOMAIN '${DOMAIN}'. Set DOMAIN in .env." >&2
  exit 1
fi
if [[ ! "$HTTP_PORT" =~ ^[0-9]+$ ]] || [[ "$HTTP_PORT" -lt 1 ]] || [[ "$HTTP_PORT" -gt 65535 ]]; then
  echo "Invalid HTTP_PORT '${HTTP_PORT}'." >&2
  exit 1
fi

SITE_FILE="${DOMAIN}.conf"
DEST="${SITE_AVAILABLE}/${SITE_FILE}"
SSL_DEST="${SITE_AVAILABLE}/${DOMAIN}-le-ssl.conf"

echo "Installing Apache modules (proxy, headers, rewrite, ssl, http2)…"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq apache2 >/dev/null

# HTTP/2 needs event or worker MPM (prefork is incompatible).
if apache2ctl -M 2>/dev/null | grep -q 'mpm_prefork_module'; then
  echo "Switching Apache MPM from prefork to event (required for HTTP/2)…"
  a2dismod mpm_prefork >/dev/null 2>&1 || true
  a2enmod mpm_event >/dev/null
fi

a2enmod proxy proxy_http headers rewrite ssl http2 >/dev/null

# Normalize forwarded headers on THIS domain's Certbot SSL vhost only.
FIX_SSL_PROTO=0
for f in "$SSL_DEST" "${SITE_ENABLED}/${DOMAIN}-le-ssl.conf"; do
  [[ -f "$f" || -L "$f" ]] || continue
  target="$f"
  if [[ -L "$f" ]]; then
    target="$(readlink -f "$f")"
  fi
  [[ -f "$target" ]] || continue
  if grep -q 'ProxyPass' "$target" && grep -q 'SSLEngine on' "$target"; then
    if grep -q 'X-Forwarded-Proto' "$target"; then
      sed -i 's/RequestHeader set X-Forwarded-Proto "http"/RequestHeader set X-Forwarded-Proto "https"/g' "$target"
    else
      if grep -q 'ProxyPreserveHost' "$target"; then
        sed -i '/ProxyPreserveHost/a\  RequestHeader set X-Forwarded-Proto "https"\n  RequestHeader set X-Forwarded-Port "443"' "$target"
      else
        sed -i '/ProxyPass /i\  RequestHeader set X-Forwarded-Proto "https"\n  RequestHeader set X-Forwarded-Port "443"' "$target"
      fi
    fi
    if ! grep -q 'X-Real-IP' "$target"; then
      if grep -q 'X-Forwarded-Proto' "$target"; then
        sed -i '/X-Forwarded-Proto/a\  RequestHeader set X-Real-IP %{REMOTE_ADDR}s' "$target"
      elif grep -q 'ProxyPreserveHost' "$target"; then
        sed -i '/ProxyPreserveHost/a\  RequestHeader set X-Real-IP %{REMOTE_ADDR}s' "$target"
      fi
    fi
    FIX_SSL_PROTO=1
  fi
done
if [[ "${FIX_SSL_PROTO:-0}" -eq 1 ]]; then
  echo "Normalized X-Forwarded-Proto=https on ${DOMAIN} SSL vhost."
fi

if [[ ! -f "$HTTP2_CONF" ]]; then
  echo "Missing HTTP/2 conf: $HTTP2_CONF" >&2
  exit 1
fi
# Shared global Protocols line — identical across projects; safe to refresh.
install -m 0644 "$HTTP2_CONF" "${CONF_AVAILABLE}/http2.conf"
a2enconf http2 >/dev/null

if [[ ! -f "$PROXY_TLS_CONF" ]]; then
  echo "Missing proxy TLS conf: $PROXY_TLS_CONF" >&2
  exit 1
fi
install -m 0644 "$PROXY_TLS_CONF" "${CONF_AVAILABLE}/${PROXY_TLS_NAME}.conf"
a2enconf "$PROXY_TLS_NAME" >/dev/null

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

HAS_CERT=0
if [[ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
  HAS_CERT=1
fi

# Render HTTP vhost: ServerName / Alias / log names / proxy port.
sed \
  -e "s/ServerName goum\\.eu/ServerName ${DOMAIN}/" \
  -e "s/ServerAlias www\\.goum\\.eu/ServerAlias www.${DOMAIN}/" \
  -e "s#http://127\\.0\\.0\\.1:8090/#http://127.0.0.1:${HTTP_PORT}/#g" \
  -e "s#http://goum\\.eu/#http://${DOMAIN}/#g" \
  -e "s#https://goum\\.eu/#https://${DOMAIN}/#g" \
  -e "s#http://www\\.goum\\.eu/#http://www.${DOMAIN}/#g" \
  -e "s#https://www\\.goum\\.eu/#https://www.${DOMAIN}/#g" \
  -e "s/goum\\.eu-error\\.log/${DOMAIN}-error.log/g" \
  -e "s/goum\\.eu-access\\.log/${DOMAIN}-access.log/g" \
  "$TEMPLATE" > "$TMP"

if [[ "$HAS_CERT" -eq 1 ]]; then
  awk '
    /__GOUM_HTTP_MODE_SECURE_BEGIN__/ {p=1; next}
    /__GOUM_HTTP_MODE_SECURE_END__/ {p=0; next}
    p {print}
  ' "$TMP" > "${TMP}.mode"
  HTTP_MODE="secure (301 → HTTPS)"
else
  awk '
    /__GOUM_HTTP_MODE_BOOTSTRAP_BEGIN__/ {p=1; next}
    /__GOUM_HTTP_MODE_BOOTSTRAP_END__/ {p=0; next}
    p {print}
  ' "$TMP" > "${TMP}.mode"
  HTTP_MODE="bootstrap (proxy cleartext until certbot)"
fi
mv "${TMP}.mode" "$TMP"

install -m 0644 "$TMP" "$DEST"

# Certbot SSL vhost: must proxy to Docker. After HTTP is switched to
# "redirect only", Certbot can regenerate le-ssl without ProxyPass → Apache 403.
SSL_SNIPPET="$ROOT/deploy/apache-ssl-proxy.snippet"
ensure_ssl_proxy() {
  local dest="$1"
  [[ -f "$dest" ]] || return 0
  grep -q 'SSLEngine on' "$dest" || return 0

  if grep -q 'ProxyPass' "$dest"; then
    sed -i -E "s#http://127\\.0\\.0\\.1:[0-9]+/#http://127.0.0.1:${HTTP_PORT}/#g" "$dest"
  else
    if [[ ! -f "$SSL_SNIPPET" ]]; then
      echo "Missing SSL proxy snippet: $SSL_SNIPPET" >&2
      exit 1
    fi
    echo "Injecting ProxyPass → 127.0.0.1:${HTTP_PORT} into $(basename "$dest")…"
    local blockf
    blockf="$(mktemp)"
    sed \
      -e "s/__HTTP_PORT__/${HTTP_PORT}/g" \
      -e "s/__DOMAIN__/${DOMAIN}/g" \
      "$SSL_SNIPPET" > "$blockf"
    awk -v blockfile="$blockf" '
      /<\/VirtualHost>/ && !done {
        while ((getline line < blockfile) > 0) print line
        close(blockfile)
        done=1
      }
      { print }
    ' "$dest" > "${dest}.tmp"
    rm -f "$blockf"
    mv "${dest}.tmp" "$dest"
  fi

  # HTTPS must advertise https to the app (not leftover "http" from bootstrap copy).
  sed -i 's/RequestHeader set X-Forwarded-Proto "http"/RequestHeader set X-Forwarded-Proto "https"/g' "$dest"
  if ! grep -q 'X-Forwarded-Proto' "$dest"; then
    sed -i '/ProxyPreserveHost/a\  RequestHeader set X-Forwarded-Proto "https"\n  RequestHeader set X-Forwarded-Port "443"' "$dest"
  fi
  if ! grep -q 'X-Real-IP' "$dest"; then
    sed -i '/X-Forwarded-Proto/a\  RequestHeader set X-Real-IP %{REMOTE_ADDR}s' "$dest"
  fi
}

ensure_ssl_proxy "$SSL_DEST"
# Also fix enabled symlink target if different path
if [[ -L "${SITE_ENABLED}/${DOMAIN}-le-ssl.conf" ]]; then
  ensure_ssl_proxy "$(readlink -f "${SITE_ENABLED}/${DOMAIN}-le-ssl.conf")"
fi

# Enable only this site — do not a2dissite other vhosts.
a2ensite "$SITE_FILE" >/dev/null
if [[ -f "$SSL_DEST" ]]; then
  a2ensite "${DOMAIN}-le-ssl.conf" >/dev/null 2>&1 || true
fi

apache2ctl configtest
systemctl enable apache2 >/dev/null
systemctl reload apache2

echo ""
echo "Host vhost installed (other sites untouched):"
echo "  domain:     ${DOMAIN} (www.${DOMAIN})"
echo "  http :80:   ${HTTP_MODE}"
if [[ -f "$SSL_DEST" ]]; then
  echo "  https:      ${DOMAIN}-le-ssl.conf → http://127.0.0.1:${HTTP_PORT}/"
else
  echo "  https:      (no ${DOMAIN}-le-ssl.conf yet — run make certbot)"
fi
echo "  site file:  ${DEST}"
echo "  http2:      conf-available/http2.conf"
echo "  proxy tls:  conf-available/${PROXY_TLS_NAME}.conf"
echo "  email hint: ${CERT_EMAIL:-set CONTACT_MAIL in .env for make certbot}"
echo ""
if [[ "$HAS_CERT" -eq 0 ]]; then
  echo "No Let's Encrypt cert yet. After DNS A/AAAA points here: make certbot"
  echo "Or re-run make deploy with CONTACT_MAIL set (deploy will call certbot)."
fi
echo ""
