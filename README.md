# Godot-Runner-Game

Endless runner built with Godot 4 — secure online scoring via the Go backend.

![Gameplay](https://media.giphy.com/media/pgkqWggvUUd7e3iprE/giphy.gif)

## Production deploy (GitHub Pages)

1. **Backend** — deploy [game-backend-go](https://github.com/NipunSGeeTH/game-backend-go) with Docker (see its README). Set in `.env`:
   - `JWT_SECRET` — long random string
   - `DATABASE_URL` — MySQL connection
   - `CORS_ORIGIN=https://moraspirit.github.io` (your Pages origin, no trailing slash)

2. **Frontend repo variable** — `Settings → Secrets and variables → Actions → Variables`:
   - `API_BASE_URL` = `https://your-api-domain.com` (HTTPS, no trailing slash)

3. **Pages** — `Settings → Pages → Source: GitHub Actions`

4. Push to `master` / `main` — workflow exports release build with `DEBUG_API=false` and your API URL baked in.

## Local development

- Open in Godot 4.6+, press Play.
- `scripts/secure/sim_constants.gd`: `API_BASE = "http://localhost:8080"`, set `DEBUG_API = true` for HTTP logs.
- Web export test: `python3 serve.py` (HTTPS on port 8000, needs `cert.pem` / `key.pem`).

## Docs

- [`docs/ANTI-CHEAT.md`](docs/ANTI-CHEAT.md) — anti-cheat overview, HMAC signing in detail, hardening checklist
- [`docs/WEB-CACHE-VERSION.md`](docs/WEB-CACHE-VERSION.md) — cached WASM/PCK updates without re-download every visit
- `docs/godot-web-frontend-integration.md` — auth, API, menu flow
- `docs/godot-web-secure-client.md` — secure spawn / HMAC client design
