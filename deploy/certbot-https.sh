#!/usr/bin/env bash
# Obtain / renew Let's Encrypt certs via Certbot Apache plugin (Ubuntu).
# Only requests certificates for this project's domain (+ www).
# Enables HTTPS redirect and the system certbot.timer for auto-renewal.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT/.env}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root (make certbot uses sudo)." >&2
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

SITE_URL="$(env_get SITE_URL "")"
DOMAIN_RAW="$(env_get DOMAIN "")"
if [[ -z "$DOMAIN_RAW" ]]; then
  DOMAIN_RAW="$(env_get DEPLOY_DOMAIN "")"
fi
EMAIL="$(env_get CONTACT_MAIL "")"
if [[ -z "$EMAIL" ]]; then
  EMAIL="$(env_get CERTBOT_EMAIL "")"
fi
STAGING="$(env_get CERTBOT_STAGING 0)"
HTTP_PORT="$(env_get HTTP_PORT 8090)"

if [[ -z "$DOMAIN_RAW" && -n "$SITE_URL" ]]; then
  DOMAIN_RAW="$(printf '%s' "$SITE_URL" | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://##' | cut -d/ -f1 | cut -d: -f1)"
fi
if [[ -z "$DOMAIN_RAW" ]]; then
  DOMAIN_RAW="goum.eu"
fi
DOMAIN="$(printf '%s' "$DOMAIN_RAW" | tr '[:upper:]' '[:lower:]')"
DOMAIN="${DOMAIN#www.}"

if [[ ! "$DOMAIN" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]]; then
  echo "Invalid DOMAIN '${DOMAIN}'. Set DOMAIN in .env." >&2
  exit 1
fi
if [[ -z "$EMAIL" || "$EMAIL" != *@* ]]; then
  echo "Set CONTACT_MAIL in .env (site display + Let's Encrypt)." >&2
  exit 1
fi

SITE_FILE="/etc/apache2/sites-available/${DOMAIN}.conf"
if [[ ! -f "$SITE_FILE" ]]; then
  echo "Missing Apache site ${SITE_FILE}. Run: make deploy" >&2
  exit 1
fi

echo "Installing Certbot (apache plugin)…"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq certbot python3-certbot-apache >/dev/null

if apache2ctl -M 2>/dev/null | grep -q 'mpm_prefork_module'; then
  echo "Switching Apache MPM from prefork to event (required for HTTP/2)…"
  a2dismod mpm_prefork >/dev/null 2>&1 || true
  a2enmod mpm_event >/dev/null
fi
a2enmod ssl headers rewrite http2 >/dev/null
if [[ -f "$ROOT/deploy/apache-http2.conf" ]]; then
  install -m 0644 "$ROOT/deploy/apache-http2.conf" /etc/apache2/conf-available/http2.conf
  a2enconf http2 >/dev/null
fi
apache2ctl configtest >/dev/null
systemctl reload apache2

CERTBOT_ARGS=(
  --apache
  --cert-name "$DOMAIN"
  -d "$DOMAIN"
  -d "www.${DOMAIN}"
  --email "$EMAIL"
  --agree-tos
  --no-eff-email
  --redirect
  --non-interactive
  --keep-until-expiring
)

if [[ "$STAGING" == "1" || "$STAGING" == "true" ]]; then
  CERTBOT_ARGS+=(--staging)
  echo "Using Let's Encrypt staging (CERTBOT_STAGING=1)."
fi

echo "Requesting / refreshing certificate for ${DOMAIN} and www.${DOMAIN} only…"
certbot "${CERTBOT_ARGS[@]}"

# Point Certbot SSL vhost at this project's Docker port (scoped to this domain).
SSL_DEST="/etc/apache2/sites-available/${DOMAIN}-le-ssl.conf"
if [[ -f "$SSL_DEST" ]] && grep -q 'ProxyPass' "$SSL_DEST"; then
  sed -i -E "s#http://127\\.0\\.0\\.1:[0-9]+/#http://127.0.0.1:${HTTP_PORT}/#g" "$SSL_DEST"
  if grep -q 'X-Forwarded-Proto "http"' "$SSL_DEST"; then
    sed -i 's/RequestHeader set X-Forwarded-Proto "http"/RequestHeader set X-Forwarded-Proto "https"/g' "$SSL_DEST"
  fi
fi

# Ubuntu ships certbot.timer for twice-daily renew attempts (system-wide, safe).
systemctl enable --now certbot.timer >/dev/null 2>&1 || true
if systemctl is-enabled certbot.timer >/dev/null 2>&1; then
  echo "certbot.timer enabled (automatic renew)."
else
  echo "Warning: certbot.timer not enabled. Add a cron job: certbot renew --quiet" >&2
fi

echo ""
echo "Renew dry-run…"
certbot renew --dry-run --cert-name "$DOMAIN"

a2enmod http2 >/dev/null
a2enconf http2 >/dev/null 2>&1 || true
apache2ctl configtest >/dev/null
systemctl reload apache2

# Re-apply HTTP→HTTPS vhost for this domain only.
if [[ -x "$ROOT/deploy/install-host-apache.sh" ]]; then
  echo "Refreshing host vhost (HTTP redirect + HSTS conf)…"
  ENV_FILE="$ENV_FILE" "$ROOT/deploy/install-host-apache.sh"
fi

echo ""
echo "HTTPS ready: https://${DOMAIN}/"
echo "HTTP check:  curl -sI http://${DOMAIN}/ | grep -iE '^(HTTP|Location|Strict)'"
echo "HTTPS check: curl -sI --http2 https://${DOMAIN}/ | grep -iE '^(HTTP|Strict)'"
echo "Auto-renew:  systemctl status certbot.timer"
echo "Manual renew: sudo certbot renew --cert-name ${DOMAIN}"
echo ""
