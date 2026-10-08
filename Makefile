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

.PHONY: build rebuild start restart stop logs perms deploy certbot apache-check

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

## Make www readable by nginx (needed after adding mp3s with tight umask)
perms:
	chmod -R a+rX www/mp3 www/assets www/chart www/index.html www/robots.txt www/sitemap.xml

stop:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f $(SERVICE)

apache-check:
	@echo "Domain:  $(DOMAIN)  ($(SITE_URL))"
	@echo "Port:    $(HTTP_PORT)  bind=$(HTTP_BIND)"
	@echo "1) Edit .env (DOMAIN, HTTP_PORT, CONTACT_MAIL, CONTACT_PHONE)"
	@echo "2) make deploy"
	@echo "3) make certbot  # if CONTACT_MAIL was empty on deploy"

## Deploy: container on loopback + Apache vhost → container + optional certbot
deploy:
	@chmod +x deploy/install-host-apache.sh deploy/certbot-https.sh
	@test -f "$(ENV_FILE)" || (echo "Missing $(ENV_FILE). Copy .env.example → .env." >&2; exit 1)
	@echo "Starting containers on 127.0.0.1:$(HTTP_PORT) (Apache will proxy)…"
	HTTP_BIND=127.0.0.1 HTTP_PORT=$(HTTP_PORT) $(COMPOSE) up -d --build
	sudo ENV_FILE="$(abspath $(ENV_FILE))" ./deploy/install-host-apache.sh
	@if grep -qE '^CONTACT_MAIL=.+@' "$(ENV_FILE)"; then \
		echo "CONTACT_MAIL set — running certbot…"; \
		sudo ENV_FILE="$(abspath $(ENV_FILE))" ./deploy/certbot-https.sh; \
	else \
		echo "Skip certbot (set CONTACT_MAIL in .env, then: make certbot)"; \
	fi
	@echo "$(SITE_URL)/"

## Let's Encrypt HTTPS + renew timer (this domain only)
certbot:
	@chmod +x deploy/certbot-https.sh
	@test -f "$(ENV_FILE)" || (echo "Missing $(ENV_FILE). Copy .env.example → .env." >&2; exit 1)
	sudo ENV_FILE="$(abspath $(ENV_FILE))" ./deploy/certbot-https.sh
