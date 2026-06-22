# Web cache and version updates

When you deploy a new frontend or backend, players may still have **old WASM/PCK files** in the browser cache. That causes broken runs, API errors, or `INVALID_SIM_VERSION` rejections.

This project uses a **two-layer** fix: smart caching (no full re-download every visit) + version checks (clear message when an update is required).

---

## How it works

### Layer 1 — Versioned asset URLs (cache busting only when you ship)

After each Godot web export, CI runs `scripts/post_export_web.py`:

| File | Role |
|------|------|
| `index.html` | Small shell — **always re-fetched** (no-cache meta) |
| `version.json` | Tiny `{ "build": "abc123", "sim_version": 6 }` — few bytes |
| `index.abc123.js` | Loader — **new URL only when you deploy** |
| `index.abc123.wasm` | Engine (~37 MB) — cached until build id changes |
| `index.abc123.pck` | Game data (~23 MB) — cached until build id changes |

**Normal visit (same deploy):** browser loads cached `index.*.wasm` and `index.*.pck` — fast.

**After you deploy:** new `index.html` points to `index.def456.wasm`. Browser downloads new files **once**, then caches them again.

Old WASM is never used because the HTML no longer references it.

### Layer 2 — Stale HTML detection

If a user’s browser cached an old `index.html`, a small inline script compares:

- `meta[name=runner-build]` on the page
- `version.json` from the server (fetched with `cache: no-store`)

If they differ → **one automatic reload** to pick up the new shell.

### Layer 3 — Server sim version check

`GET /v1/meta` returns:

```json
{
  "sim_version": 6,
  "min_sim_version": 6
}
```

On the menu, `VersionCheck` compares `SimConstants.SIM_VERSION` with `min_sim_version`. If the client is too old → **“Please refresh the page”** and PLAY is disabled.

When you change spawn logic or physics, **bump `SIM_VERSION`** in both:

- `Godot-Runner-Game/scripts/secure/sim_constants.gd`
- `run-game-backend-go/internal/sim/constants.go`

---

## What you must do when releasing

### Frontend-only change (UI, sounds, no sim change)

1. Push to `main` / `master` → GitHub Actions exports and runs `post_export_web.py`
2. New build id in filenames → users get new PCK/WASM on next visit (cached after that)
3. **Do not** bump `SIM_VERSION`

### Gameplay / spawn / anti-cheat change

1. Bump `SIM_VERSION` in **Godot and Go** (same integer)
2. Deploy backend first (or together with frontend)
3. Old cached clients hit `/v1/meta` → refresh prompt; old move logs get `INVALID_SIM_VERSION`

### Backend-only API change (no sim change)

1. Deploy backend
2. If response shape changed, you may still need a frontend deploy
3. `SIM_VERSION` unchanged unless replay rules changed

---

## Local testing

```bash
godot --headless --export-release Web build/web/index.html
BUILD_ID=localtest SIM_VERSION=6 python3 scripts/post_export_web.py
python3 serve.py
```

Open the HTTPS URL — you should see `index.localtest.wasm` in Network tab, not plain `index.wasm`.

---

## FAQ

**Do users download WASM every time they open the game?**  
No. Only when `build` id in the URL changes (new deploy).

**What if someone keeps an old tab open for days?**  
Next menu load calls `/v1/meta`. If `SIM_VERSION` is too low, they see “refresh the page”.

**Can I force everyone to update immediately?**  
Bump `min_sim_version` on the server above old clients’ `SIM_VERSION`. They cannot PLAY until refresh.

**GitHub Pages and cache headers**  
We cannot set custom CDN headers on `github.io`. Versioned filenames + `version.json` check are the reliable approach.

---

## Files

| File | Purpose |
|------|---------|
| `scripts/post_export_web.py` | CI post-process — rename assets, write `version.json` |
| `.github/workflows/deploy-pages.yml` | Sets `CLIENT_BUILD`, runs post-export |
| `scripts/secure/version_check.gd` | Menu startup `/v1/meta` check |
| `run-game-backend-go/internal/api/server.go` | `GET /v1/meta` |
