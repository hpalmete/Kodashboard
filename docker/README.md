# KoDashboard in Docker

Runs the KoDashboard plugin's dashboard outside of KOReader. Point it at a
copy of your KOReader data and (optionally) your books directory; it serves
the same web UI as the in-reader plugin.

## What's different from the plugin

- **No KOReader runtime.** A tiny LuaJIT server (`docker/server.lua`)
  hosts the existing `api.lua` / `dataloader.lua` against a mounted
  data dir.
- **Cover fetching from Open Library is disabled.** Covers already cached
  on disk (under your koreader data dir or in `.sdr/cover.jpg`) still
  display.
- **New endpoint: `POST /api/refresh`** clears the in-memory dashboard
  cache so the next request re-reads the SQLite DB and sidecars from
  disk. Wired to a floating **Refresh** button in the UI.
- **`POST /api/server/stop` exits the container.** Set
  `restart: unless-stopped` in compose to bring it back automatically.

## Quick start

```bash
# from the repo root
docker compose up --build
# open http://localhost:8686
```

Edit `docker-compose.yml` to point the `./koreader-data` mount at your
actual KOReader data directory.

## What to mount

| Container path | What goes there | Required for |
|---|---|---|
| `/data/koreader` | Your KOReader data dir (must contain `settings/statistics.sqlite3`, ideally also `history.lua` and `docsettings/`) | Everything |
| (matches host path in `history.lua`) | Your books directory, mounted at the **same absolute path** KOReader recorded | Highlights, annotations, accurate book metadata when sidecars sit next to book files |

`history.lua` stores absolute book paths from your reader (e.g.
`/mnt/us/documents/Foo.epub` on a Kindle). KoDashboard reads `.sdr/`
sidecars next to those files, so the simplest setup is to mount your
books directory at the exact same path inside the container — no path
rewriting required.

If your KOReader is configured to store sidecars centrally under
`koreader/docsettings/`, you can skip the books mount entirely; the
sidecars are already inside the KO_DATA_DIR mount.

## Updating data

Copy a fresh `statistics.sqlite3` (and the `docsettings/` tree, if
applicable) into the mounted directory, then click **Refresh** in the
top-right of the UI. The cache TTL is also short (8s), so you can also
just wait.

## Environment variables

| Var | Default | Purpose |
|---|---|---|
| `PORT` | `8686` | Listening port |
| `HOST` | `0.0.0.0` | Bind address |
| `WEB_DIR` | `/app/web` | Static file root |
| `KO_DATA_DIR` | `/data/koreader` | KOReader data directory |
| `KO_SETTINGS_DIR` | `$KO_DATA_DIR/settings` | Where `statistics.sqlite3` lives |
| `KO_LOG_DEBUG` | unset | Set to any non-empty value to enable debug logs |
