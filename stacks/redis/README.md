# Redis Layer

Redis runs inside the single `data-lab` container and stores append-only files under `~/runtime/redis`.

## In-container DB access helper

If you are inside the container, use:

```bash
bash ~/redis/scripts/db_access_guide.sh
```

This prompts for username/password and prints:
- Browser UI URLs (host-side)
- PostgreSQL, MongoDB, Redis connection values for IDEs
- Ready-to-use MongoDB/Redis URI examples

## Step-by-step guide

1. Start Redis inside the container:
   ```bash
   datalab_app --start-redis
   ```
2. Example output you should see:
   ```text
   Redis listening on localhost:6379
   ```
3. Get the real mapped host ports from your host terminal:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\helper\scripts\ui-services.ps1 -Name datalab -UiHost localhost
   ```
4. In that output, find:
   - `Redis (DB): redis://localhost:<port>`
   - `Redis Commander UI: http://localhost:<port>/`
5. Open `Redis Commander UI` in browser.

## VS Code (dynamic port)

1. Install one of these extensions:
   - Name: `Redis for VS Code` (Publisher: `Redis`, id: `redis.redis-for-vscode`)
   - Alternative: `Redis Explorer` (id: `cweijan.vscode-redis-client2`)
2. Use the mapped port from `ui-services.ps1` (`Redis (DB)`):
   - Host: `localhost`
   - Port: `<mapped_redis_port>`
   - Password: `admin`
3. Test with command:
   ```text
   PING
   ```
   expected result: `PONG`

## PyCharm (dynamic port)

PyCharm Database tool does not provide first-class Redis browsing like SQL data sources.

Recommended options:

1. Use `Redis Commander UI` URL from `ui-services.ps1`.
2. Use Redis CLI:
   ```bash
   redis-cli -h localhost -p <mapped_redis_port>
   ```
3. Optional plugin in JetBrains:
   - Name: `Redis`
   - Plugin id: `12826-redis`
