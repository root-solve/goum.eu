# goum.eu

Site de **Goum** — groupe de Bondy (93) depuis 2008. Playlist live, page « Rejoindre », charte graphique et déploiement Apache derrière Docker.

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
Après ajout de fichiers en tant que `goum` : `chmod a+r www/mp3/*.mp3` (ou `make mp3-perms`) — sinon lecture **403** dans le player.

## Production

Sur le serveur (DNS prêts, ports 80/443 ouverts), en tant qu’utilisateur qui a Docker (ex. `ubuntu`) :

```bash
cd /home/goum/goum.eu
# .env + www/mp3/ en place
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

## Sécurité (rappel prod)

- `make deploy` publie le site en **127.0.0.1** seulement ; Apache termine le TLS.
- L’API n’est **pas** exposée sur l’hôte (uniquement via le proxy `/api/`).
- Ne pas committer `.env` ; mp3 hors git.
