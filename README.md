# goum.eu

Site de **Goum**, groupe de Bondy (93) depuis 2008. Playlist live, page « Rejoindre », charte graphique et déploiement Apache derrière Docker.

- Site : [goum.eu](https://goum.eu)
- Réalisé par [rootsolve.org](https://rootsolve.org)

## Stack

- **Front** : HTML / CSS / JS statiques (`www/`)
- **API** : petit service Python qui scanne `www/mp3/` (métadonnées + durées)
- **Runtime** : Docker Compose (nginx + API)
- **Prod** : Apache reverse-proxy + Certbot (`make deploy`)

## Démarrage local

```bash
cp .env.example .env   # ajuster CONTACT_*, YOUTUBE_URL, etc.
# déposer les mp3 dans www/mp3/
make start             # → http://localhost:8090
```

Commandes : `make restart`, `make stop`, `make logs`.

## Configuration (`.env`)

| Variable | Rôle |
|----------|------|
| `DOMAIN` / `SITE_URL` | Domaine public |
| `HTTP_PORT` / `HTTP_BIND` | Port Docker (8090) / bind local |
| `CONTACT_MAIL` / `CONTACT_PHONE` | Affichés sur le site + mail Certbot |
| `YOUTUBE_URL` | Lien YouTube dans le header (masqué si vide) |
| `CERTBOT_STAGING` | `1` pour tests Let’s Encrypt |

Les mp3 **ne sont pas versionnés** (`www/mp3/` + `.gitkeep`).

## Production

```bash
# .env + www/mp3/ en place, DNS prêts
make deploy            # conteneur 127.0.0.1 + vhost Apache + Certbot
```

Certificat seul : `make certbot`.

## Arborescence

```
www/           # site servi (monté live dans le conteneur)
  mp3/         # fichiers audio
  chart/       # charte graphique (noindex)
  assets/      # CSS, JS, favicon, images
api/           # service /api/tracks et /api/site
deploy/        # scripts Apache / Certbot
```
