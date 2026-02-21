# PostgreSQL Layer

PostgreSQL runs inside the single `data-lab` container and stores data under `~/runtime/postgres`.

## In-container DB access helper

If you are inside the container, use:

```bash
bash ~/postgres/scripts/db_access_guide.sh
```

This prompts for username/password and prints:
- Browser UI URLs (host-side)
- PostgreSQL, MongoDB, Redis connection values for IDEs
- Ready-to-use MongoDB/Redis URI examples

## Step-by-step guide

1. Start PostgreSQL inside the container:
   ```bash
   datalab_app --start-postgres
   ```
2. Example output you should see:
   ```text
   PostgreSQL listening on localhost:5432 (db=datalab, user=admin)
   ```
3. Get the real mapped host ports from your host terminal:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\helper\scripts\ui-services.ps1 -Name datalab -UiHost localhost
   ```
4. In that output, find:
   - `PostgreSQL (DB): postgresql://localhost:<port>`
   - `Adminer UI: http://localhost:<port>/`
5. Open the `Adminer UI` URL in browser, then login with:
   - System: `PostgreSQL`
   - Server: `localhost`
   - Username: `admin`
   - Password: `admin`
   - Database: `datalab`

## pgAdmin UI (inside the same `datalab` container)

Use this if you want pgAdmin without any extra container.

1. Make sure host port `8181` is published when creating `datalab`.
   - With helper script this is now default.
2. Start PostgreSQL + pgAdmin inside `datalab`:
   ```bash
   datalab_app --start-postgres
   datalab_app --start-pgadmin
   ```
3. From host, verify URL:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\helper\scripts\ui-services.ps1 -Name datalab -UiHost localhost
   ```
4. Open pgAdmin:
   - URL: `http://localhost:8181/`
   - Email: `admin@admin.com`
   - Password: `admin`
5. Add PostgreSQL server in pgAdmin:
   - Host: `localhost`
   - Port: `5432` (or mapped host Postgres port)
   - Username: `admin`
   - Password: `admin`

## pgAdmin UI (separate container, optional)

Use this when you want the full pgAdmin experience instead of Adminer.

1. Start PostgreSQL in your target container:
   ```bash
   datalab_app --start-postgres
   ```
2. From host terminal, start pgAdmin bound to that container:
   - For standalone container:
     ```powershell
     powershell -ExecutionPolicy Bypass -File .\helper\scripts\start-pgadmin.ps1 -TargetContainer datalab-standalone -PgAdminPort 8181
     ```
   - For compose container:
     ```powershell
     powershell -ExecutionPolicy Bypass -File .\helper\scripts\start-pgadmin.ps1 -TargetContainer data-lab -PgAdminPort 8181
     ```
3. Open pgAdmin:
   - URL: `http://localhost:8181/`
   - Email: `admin@admin.com`
   - Password: `admin`
4. A server entry is auto-created by the helper script. If prompted for DB password, use:
   - Username: `admin`
   - Password: `admin`

### Create server manually in pgAdmin (if needed)

If the auto-created entry is missing, create one manually:

1. In pgAdmin: `Servers` -> right click -> `Register` -> `Server...`
2. `General` tab:
   - Name: `Data Lab PostgreSQL`
3. `Connection` tab:
   - Host name/address: `host.docker.internal`
   - Port: host-mapped PostgreSQL port
     - `15432` for `datalab-standalone`
     - `5432` for `data-lab` compose container
   - Maintenance database: `postgres` (or `datalab`)
   - Username: `admin`
   - Password: `admin`
   - Save password: enabled
4. Click `Save`, then open `Query Tool` and run:
   ```sql
   SELECT current_database(), current_user, version();
   ```

### Common pgAdmin connection issues

- pgAdmin URL fails to open:
  - Use `http://localhost:8181/` (not `https`).
- Authentication fails:
  - Confirm PostgreSQL is running inside container: `datalab_app --start-postgres`.
- Cannot connect to server from pgAdmin:
  - Verify target container name in `start-pgadmin.ps1` matches what is running.
  - Verify DB port mapping from host:
    - `docker port datalab-standalone 5432/tcp`
    - `docker port data-lab 5432/tcp`
- Port `8181` already used:
  - Run helper with another port, for example `-PgAdminPort 8282`.

## VS Code (dynamic port)

1. Install extension:
   - Name: `PostgreSQL`
   - Publisher: `Microsoft`
   - VS Code id: `ms-ossdata.vscode-postgresql`
2. Use the port from `ui-services.ps1` (`PostgreSQL (DB)`).
3. Create connection:
   - Host: `localhost`
   - Port: `<mapped_postgres_port>`
   - Database: `datalab`
   - User: `admin`
   - Password: `admin`
   - SSL: `Disable`
4. Test query:
   ```sql
   SELECT current_database(), current_user, version();
   ```

## PyCharm (dynamic port)

1. Open `View > Tool Windows > Database`.
2. Add data source `PostgreSQL` (built-in driver).
3. Use the port from `ui-services.ps1` (`PostgreSQL (DB)`):
   - Host: `localhost`
   - Port: `<mapped_postgres_port>`
   - User: `admin`
   - Password: `admin`
   - Database: `datalab`
4. Click `Test Connection`.

## Demo

`~/postgres/example_postgres.sql` creates a sample table, inserts rows, and selects them back.
