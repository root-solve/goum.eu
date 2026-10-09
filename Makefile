ENV_FILE ?= .env
COMPOSE := docker compose --env-file $(ENV_FILE)
SERVICE := web

env_val = $(shell sed -n 's/^$(1)=//p' $(ENV_FILE) 2>/dev/null | tail -n1 | tr -d '\r')

DOMAIN := $(or $(call env_val,DOMAIN),goum.eu)
HTTP_PORT := $(or $(call env_val,HTTP_PORT),8090)
HTTP_BIND := $(or $(call env_val,HTTP_BIND),0.0.0.0)
SITE_URL := $(or $(call env_val,SITE_URL),https://$(DOMAIN))
ENDPOINT := http://localhost:$(HTTP_PORT)

.PHONY: build rebuild start restart stop logs deploy certbot

build:
	$(COMPOSE) build

rebuild:
	$(COMPOSE) build --no-cache
	$(COMPOSE) up -d --force-recreate --remove-orphans
	@echo "$(ENDPOINT)"

start:
	$(COMPOSE) up -d
	@echo "$(ENDPOINT)"

restart:
	$(COMPOSE) up -d --build --force-recreate --remove-orphans
	@echo "$(ENDPOINT)"

stop:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f $(SERVICE)

## Containers on 127.0.0.1 + Apache vhost (+ certbot if CONTACT_MAIL set)
deploy:
	@test -f "$(ENV_FILE)" || (echo "Missing $(ENV_FILE). Copy .env.example → .env." >&2; exit 1)
	@echo "Starting containers on 127.0.0.1:$(HTTP_PORT)…"
	HTTP_BIND=127.0.0.1 HTTP_PORT=$(HTTP_PORT) $(COMPOSE) up -d --build
	sudo ENV_FILE="$(abspath $(ENV_FILE))" bash deploy/install-host-apache.sh
	@if grep -qE '^CONTACT_MAIL=.+@' "$(ENV_FILE)"; then \
		echo "CONTACT_MAIL set — running certbot…"; \
		sudo ENV_FILE="$(abspath $(ENV_FILE))" bash deploy/certbot-https.sh; \
	else \
		echo "Skip certbot (set CONTACT_MAIL in .env, then: make certbot)"; \
	fi
	@echo "$(SITE_URL)/"

certbot:
	@test -f "$(ENV_FILE)" || (echo "Missing $(ENV_FILE). Copy .env.example → .env." >&2; exit 1)
	sudo ENV_FILE="$(abspath $(ENV_FILE))" bash deploy/certbot-https.sh
