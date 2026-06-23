# Upgrading existing OpenHEXA installs

This document lists the manual steps required to move an **existing**
OpenHEXA installation from one version to the next: new environment
variables, breaking changes, and one-off migration commands.

## General upgrade procedure

```bash
sudo systemctl stop openhexa
sudo apt update && sudo apt install --only-upgrade openhexa
# Pull the new app/frontend images (and any new possible images):
sudo /usr/share/openhexa/openhexa.sh -g update
# Apply Django migrations and bootstrap any new services:
sudo /usr/share/openhexa/openhexa.sh -g prepare
sudo systemctl start openhexa
```

The package post-install hook runs `update` and `prepare` automatically on a
**fresh** install. On an **upgrade** you should re-run them explicitly to
apply the Django migrations introduced since your installed version.

### Checking for new environment variables

New releases sometimes add environment variables. `update` runs an automatic
check and warns you when your `.env` is missing keys that exist in `.env.dist`.
You can run the check on demand:

```bash
# Report keys present in .env.dist but missing from your .env:
sudo /usr/share/openhexa/openhexa.sh -g env-check
# Or check an env file at a non-standard location:
sudo /usr/share/openhexa/openhexa.sh -g env-check /path/to/.env
```

---

## 5.x

OpenHEXA 5.x introduces Forgejo as a hard dependency (it backs the Static Webapps feature).

### New environment variables

Append the variables you are missing to your `.env` (the defaults in this list match
`.env.dist`).

```bash
# Forgejo Git server (required since 5.0.0, backs Static Webapps)
GIT_SERVER_ADMIN_USERNAME=openhexa-admin
GIT_SERVER_ADMIN_PASSWORD=something-secure   # set this yourself on upgrade

# Absolute path to the directory where Forgejo persists its data
# (SQLite metadata DB, git repositories, attachments, app.ini, ...).
FORGEJO_STORAGE_LOCATION=$FORGEJO_STORAGE_LOCATION

# Static Webapps
# Parent domain to serve webapps from a subdomain; leave empty to disable.
WEBAPPS_DOMAIN=
# Comma-separated custom domains attached to public webapps.
ADDITIONAL_ALLOWED_HOSTS=

# Workspace storage: new S3 backend (optional)
# IAM role to assume for short-lived notebook credentials.
WORKSPACE_STORAGE_BACKEND_AWS_ROLE_ARN=

# Datasets: max files snapshotted per dataset version (previews)
WORKSPACE_DATASETS_FILE_SNAPSHOT_SIZE=50

# AI assistant: monthly request cap per workspace
ASSISTANT_MONTHLY_LIMIT=200
# Optional Pydantic Logfire integration for AI agent observability
LOGFIRE_SEND_TO_LOGFIRE=false

# OAuth2
OAUTH2_ACCESS_TOKEN_EXPIRE_SECONDS=3600
# Comma-separated hosts allowed as OAuth2 redirect URIs.
OAUTH2_ALLOWED_REDIRECT_URI_HOSTS=

# Allow users to sign up without an invitation
ALLOW_SELF_REGISTRATION=false
```

### Breaking changes

- **Forgejo Git server** is now required. The package ships a `forgejo`
  service (image `codeberg.org/forgejo/forgejo:14`) backed by the
  `forgejo_data` volume, listening on host port `3100`. The Django backend
  reaches it over the internal Docker network at `http://forgejo:3000` (set in
  `compose.yml`, no configuration needed).
- **App service command** changed from `manage runserver` to `start`
  (gunicorn + `UvicornWorkerNoLifespan`). Required for Server Sent Events.
  details and the AI agent loop.
- **Backup/restore layout** changed: data is split into
  `<LOCATION>/workspaces` and `<LOCATION>/forgejo`, and backups now also
  capture `FORGEJO_STORAGE_LOCATION` and a snapshot of `.env`. Pre-upgrade
  backups remain readable by pointing `duplicity restore` at the old path; new
  backups start a fresh full at the new sub-prefix. See the
  [Backup section in the README](./README.md#backup) for the legacy-restore
  procedure.

### Manual steps

Run `openhexa.sh prepare` after upgrading to apply the Django migrations
introduced across the 5.x series (custom webapp domains, AI agent tables,
scheduled-run version selection, read-only table protection) and to bootstrap
the Forgejo admin user.
