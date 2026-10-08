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

ROOT := $(abspath .)
ENV_ABS := $(abspath $(ENV_FILE))
COMPOSE_FILE := $(ROOT)/docker-compose.yml
OWNER_HOME := $(shell getent passwd $(PROJECT_OWNER) | cut -d: -f6)

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
	@bash deploy/fix-perms.sh

stop:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f $(SERVICE)

apache-check:
	@echo "Domain:  $(DOMAIN)  ($(SITE_URL))"
	@echo "Port:    $(HTTP_PORT)  bind=$(HTTP_BIND)"
	@echo "Owner:   $(PROJECT_OWNER)  (must be in group docker)"
	@echo "Deploy:  make deploy  |  sudo make deploy"
	@echo "Doctor:  make doctor"

## Quick diagnosis: perms + backend + Apache
doctor:
	@bash deploy/fix-perms.sh
	@echo ""
	@echo "== path to index (other needs --x on each dir) =="
	@namei -l "$(ROOT)/www/index.html" 2>/dev/null || true
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

## Deploy: perms + containers as PROJECT_OWNER + Apache (root) + optional certbot
deploy:
	@test -f "$(ENV_ABS)" || (echo "Missing $(ENV_ABS). Copy .env.example → .env." >&2; exit 1)
	@id -u "$(PROJECT_OWNER)" >/dev/null 2>&1 || (echo "PROJECT_OWNER=$(PROJECT_OWNER) does not exist" >&2; exit 1)
	@bash deploy/fix-perms.sh
	@echo "Ensure $(PROJECT_OWNER) is in group docker…"
	@if [ "$$(id -u)" -eq 0 ]; then \
		id -nG "$(PROJECT_OWNER)" | grep -qw docker || usermod -aG docker "$(PROJECT_OWNER)"; \
	else \
		sudo bash -c 'id -nG "$(PROJECT_OWNER)" | grep -qw docker || usermod -aG docker "$(PROJECT_OWNER)"'; \
	fi
	@echo "Starting containers on 127.0.0.1:$(HTTP_PORT) as $(PROJECT_OWNER)…"
	@if [ "$$(id -un)" = "$(PROJECT_OWNER)" ]; then \
		HTTP_BIND=127.0.0.1 HTTP_PORT="$(HTTP_PORT)" \
			docker compose --env-file "$(ENV_ABS)" -f "$(COMPOSE_FILE)" \
			--project-directory "$(ROOT)" up -d --build; \
	elif [ "$$(id -u)" -eq 0 ]; then \
		runuser -u "$(PROJECT_OWNER)" -- env HOME="$(OWNER_HOME)" \
			HTTP_BIND=127.0.0.1 HTTP_PORT="$(HTTP_PORT)" \
			docker compose --env-file "$(ENV_ABS)" -f "$(COMPOSE_FILE)" \
			--project-directory "$(ROOT)" up -d --build; \
	else \
		sudo runuser -u "$(PROJECT_OWNER)" -- env HOME="$(OWNER_HOME)" \
			HTTP_BIND=127.0.0.1 HTTP_PORT="$(HTTP_PORT)" \
			docker compose --env-file "$(ENV_ABS)" -f "$(COMPOSE_FILE)" \
			--project-directory "$(ROOT)" up -d --build; \
	fi
	@if [ "$$(id -u)" -eq 0 ]; then \
		ENV_FILE="$(ENV_ABS)" bash deploy/install-host-apache.sh; \
	else \
		sudo ENV_FILE="$(ENV_ABS)" bash deploy/install-host-apache.sh; \
	fi
	@has_mail=0; \
	if [ "$$(id -u)" -eq 0 ]; then \
		grep -qE '^CONTACT_MAIL=.+@' "$(ENV_ABS)" && has_mail=1 || true; \
	else \
		sudo grep -qE '^CONTACT_MAIL=.+@' "$(ENV_ABS)" && has_mail=1 || true; \
	fi; \
	if [ "$$has_mail" -eq 1 ]; then \
		echo "CONTACT_MAIL set — running certbot…"; \
		if [ "$$(id -u)" -eq 0 ]; then ENV_FILE="$(ENV_ABS)" bash deploy/certbot-https.sh; \
		else sudo ENV_FILE="$(ENV_ABS)" bash deploy/certbot-https.sh; fi; \
	else \
		echo "Skip certbot (set CONTACT_MAIL in .env, then: make certbot)"; \
	fi
	@echo ""
	@curl -sS -o /dev/null -w "backend  http://127.0.0.1:$(HTTP_PORT)/ → %{http_code}\n" "http://127.0.0.1:$(HTTP_PORT)/" || true
	@curl -sS -o /dev/null -w "public   $(SITE_URL)/ → %{http_code}\n" "$(SITE_URL)/" || true
	@echo "$(SITE_URL)/"

## Let's Encrypt HTTPS + renew timer (this domain only)
certbot:
	@test -f "$(ENV_ABS)" || (echo "Missing $(ENV_ABS). Copy .env.example → .env." >&2; exit 1)
	@if [ "$$(id -u)" -eq 0 ]; then \
		ENV_FILE="$(ENV_ABS)" bash deploy/certbot-https.sh; \
	else \
		sudo ENV_FILE="$(ENV_ABS)" bash deploy/certbot-https.sh; \
	fi
