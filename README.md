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
make perms             # si nginx renvoie 403
make start             # → http://localhost:8090
```

Commandes utiles : `make restart` (recree avec le `.env`), `make stop`, `make logs`.

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

Sur le serveur (DNS `goum.eu` / `www` prêts, ports 80/443 ouverts) :

```bash
# repo + .env + fichiers www/mp3/
make deploy            # conteneur en 127.0.0.1 + vhost Apache + Certbot
```

Certificat seul : `make certbot`. Le vhost ne touche pas aux autres sites Apache.

## Arborescence

```
www/           # site servi (monté live dans le conteneur)
  mp3/         # fichiers audio
  chart/       # charte graphique (noindex)
  assets/      # CSS, JS, favicon, images
api/           # service /api/tracks et /api/site
deploy/        # scripts Apache / Certbot
```

Éditer HTML/CSS/JS ou ajouter des mp3 sur l’hôte suffit — pas de rebuild pour le contenu.

## Sécurité (rappel prod)

- `make deploy` publie le site en **127.0.0.1** seulement ; Apache termine le TLS.
- L’API n’est **pas** exposée sur l’hôte (uniquement via nginx `/api/`).
- Ne pas committer `.env` ; mp3 hors git.
- Après deploy : vérifier HSTS / HTTPS et que le port `HTTP_PORT` n’est pas ouvert publiquement.