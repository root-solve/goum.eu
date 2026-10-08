ENV_FILE ?= .env
COMPOSE := docker compose --env-file $(ENV_FILE)
SERVICE := web

# Read selected keys for make output (compose uses --env-file directly)
env_val = $(shell sed -n 's/^$(1)=//p' $(ENV_FILE) 2>/dev/null | tail -n1 | tr -d '\r')

DOMAIN := $(or $(call env_val,DOMAIN),goum.eu)
HTTP_PORT := $(or $(call env_val,HTTP_PORT),8090)
HTTP_BIND := $(or $(call env_val,HTTP_BIND),0.0.0.0)
SITE_URL := $(or $(call env_val,SITE_URL),https://$(DOMAIN))
ENDPOINT := http://localhost:$(HTTP_PORT)
PROJECT_OWNER := $(or $(call env_val,PROJECT_OWNER),goum)

# If `sudo make deploy`, run Docker as the real user (not root).
COMPOSE_USER := $(if $(SUDO_USER),$(SUDO_USER),$(shell id -un))

.PHONY: build rebuild start restart stop logs perms deploy certbot apache-check doctor

## Build the image
build:
	$(COMPOSE) build

## Rebuild from scratch (no cache) and recreate the container
rebuild:
	$(COMPOSE) build --no-cache
	$(COMPOSE) up -d --force-recreate --remove-orphans
	@echo "$(ENDPOINT)"

## Start the site (uses values from .env)
start:
	$(COMPOSE) up -d
	@echo "$(ENDPOINT)"

## Recreate containers so .env + image code changes apply
restart:
	$(COMPOSE) up -d --build --force-recreate --remove-orphans
	@echo "$(ENDPOINT)"

## Ownership (PROJECT_OWNER) + path traversal so the container behind Apache can read www/
perms:
	@chmod +x deploy/fix-perms.sh
	ENV_FILE="$(abspath $(ENV_FILE))" ./deploy/fix-perms.sh

stop:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f $(SERVICE)

apache-check:
	@echo "Domain:  $(DOMAIN)  ($(SITE_URL))"
	@echo "Port:    $(HTTP_PORT)  bind=$(HTTP_BIND)"
	@echo "Owner:   $(PROJECT_OWNER)"
	@echo "1) As $(PROJECT_OWNER): git pull && make deploy"
	@echo "   (or: sudo make deploy — Docker still runs as $(COMPOSE_USER))"
	@echo "2) make doctor  # if Forbidden / 403"

## Quick diagnosis: perms + backend + Apache
doctor:
	@chmod +x deploy/fix-perms.sh
	@echo "== perms =="
	ENV_FILE="$(abspath $(ENV_FILE))" ./deploy/fix-perms.sh
	@echo ""
	@echo "== home traverse (need ---x--x or better on other) =="
	@namei -l "$(abspath .)/www/index.html" 2>/dev/null || ls -ld /home /home/* "$(abspath .)" www 2>/dev/null || true
	@echo ""
	@echo "== backend (what Apache proxies to) =="
	@curl -sS -o /dev/null -w "http://127.0.0.1:$(HTTP_PORT)/ → HTTP %{http_code}\n" "http://127.0.0.1:$(HTTP_PORT)/" || echo "backend unreachable"
	@echo ""
	@echo "== Apache SSL proxy =="
	@if [ -f "/etc/apache2/sites-available/$(DOMAIN)-le-ssl.conf" ]; then \
		grep -n 'ProxyPass\|SSLEngine\|DocumentRoot' "/etc/apache2/sites-available/$(DOMAIN)-le-ssl.conf" || true; \
	else \
		echo "missing $(DOMAIN)-le-ssl.conf (run make certbot)"; \
	fi
	@echo ""
	@echo "== public =="
	@curl -sS -o /dev/null -w "https://$(DOMAIN)/ → HTTP %{http_code}\n" "https://$(DOMAIN)/" || true

## Deploy: perms + container on loopback + Apache vhost + optional certbot
deploy:
	@chmod +x deploy/install-host-apache.sh deploy/certbot-https.sh deploy/fix-perms.sh
	@test -f "$(ENV_FILE)" || (echo "Missing $(ENV_FILE). Copy .env.example → .env." >&2; exit 1)
	@$(MAKE) perms
	@echo "Starting containers on 127.0.0.1:$(HTTP_PORT) as user $(COMPOSE_USER)…"
	@if [ "$$(id -u)" -eq 0 ]; then \
		runuser -u "$(COMPOSE_USER)" -- env HTTP_BIND=127.0.0.1 HTTP_PORT="$(HTTP_PORT)" \
			docker compose --env-file "$(abspath $(ENV_FILE))" \
			-f "$(abspath .)/docker-compose.yml" up -d --build; \
	else \
		HTTP_BIND=127.0.0.1 HTTP_PORT=$(HTTP_PORT) $(COMPOSE) up -d --build; \
	fi
	@if [ "$$(id -u)" -eq 0 ]; then \
		ENV_FILE="$(abspath $(ENV_FILE))" ./deploy/install-host-apache.sh; \
	else \
		sudo ENV_FILE="$(abspath $(ENV_FILE))" ./deploy/install-host-apache.sh; \
	fi
	@if grep -qE '^CONTACT_MAIL=.+@' "$(ENV_FILE)"; then \
		echo "CONTACT_MAIL set — running certbot…"; \
		if [ "$$(id -u)" -eq 0 ]; then \
			ENV_FILE="$(abspath $(ENV_FILE))" ./deploy/certbot-https.sh; \
		else \
			sudo ENV_FILE="$(abspath $(ENV_FILE))" ./deploy/certbot-https.sh; \
		fi; \
	else \
		echo "Skip certbot (set CONTACT_MAIL in .env, then: make certbot)"; \
	fi
	@echo ""
	@curl -sS -o /dev/null -w "backend  http://127.0.0.1:$(HTTP_PORT)/ → %{http_code}\n" "http://127.0.0.1:$(HTTP_PORT)/" || true
	@curl -sS -o /dev/null -w "public   $(SITE_URL)/ → %{http_code}\n" "$(SITE_URL)/" || true
	@echo "$(SITE_URL)/"

## Let's Encrypt HTTPS + renew timer (this domain only)
certbot:
	@chmod +x deploy/certbot-https.sh
	@test -f "$(ENV_FILE)" || (echo "Missing $(ENV_FILE). Copy .env.example → .env." >&2; exit 1)
	@if [ "$$(id -u)" -eq 0 ]; then \
		ENV_FILE="$(abspath $(ENV_FILE))" ./deploy/certbot-https.sh; \
	else \
		sudo ENV_FILE="$(abspath $(ENV_FILE))" ./deploy/certbot-https.sh; \
	fi
