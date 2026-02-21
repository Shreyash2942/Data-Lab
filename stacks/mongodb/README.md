# MongoDB Layer

MongoDB runs inside the single `data-lab` container and stores data under `~/runtime/mongodb`.

## In-container DB access helper

If you are inside the container, use:

```bash
bash ~/mongodb/scripts/db_access_guide.sh
```

This prompts for username/password and prints:
- Browser UI URLs (host-side)
- PostgreSQL, MongoDB, Redis connection values for IDEs
- Ready-to-use MongoDB/Redis URI examples

## Step-by-step guide

1. Start MongoDB inside the container:
   ```bash
   datalab_app --start-mongodb
   ```
2. Example output you should see:
   ```text
   MongoDB listening on localhost:27017 (db=datalab, auth=true)
   ```
3. Get the real mapped host ports from your host terminal:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\helper\scripts\ui-services.ps1 -Name datalab -UiHost localhost
   ```
4. In that output, find:
   - `MongoDB (DB): mongodb://localhost:<port>`
   - `Mongo Express UI: http://localhost:<port>/`
5. Open `Mongo Express UI` in browser.

Default Mongo credentials:

- Username: `admin`
- Password: `admin`
- Auth database: `admin`

## VS Code (dynamic port)

1. Install extension:
   - Name: `MongoDB for VS Code`
   - Publisher: `MongoDB`
   - VS Code id: `mongodb.mongodb-vscode`
2. Use the port from `ui-services.ps1` (`MongoDB (DB)`).
3. Build URI:
   ```text
   mongodb://admin:admin@localhost:<mapped_mongo_port>/admin?authSource=admin
   ```
4. Connect and run:
   ```javascript
   use("datalab");
   db.sample_collection.find().limit(5);
   ```

## PyCharm (dynamic port)

1. Open `View > Tool Windows > Database`.
2. Add data source `MongoDB`.
3. Use connection string with mapped port:
   ```text
   mongodb://admin:admin@localhost:<mapped_mongo_port>/admin?authSource=admin
   ```
4. Click `Test Connection`.
