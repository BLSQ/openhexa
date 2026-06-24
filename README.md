<div align="center">
   <img alt="OpenHEXA Logo" src="https://raw.githubusercontent.com/BLSQ/openhexa-app/main/backend/hexa/static/img/logo/logo_with_text_black.svg" height="80">
</div>
<p align="center">
    <em>Open-source data integration and analysis platform</em>
</p>

[![build_debian_package](https://github.com/BLSQ/openhexa/actions/workflows/build_debian_package.yml/badge.svg)](https://github.com/BLSQ/openhexa/actions/workflows/build_debian_package.yml)

# OpenHEXA

OpenHEXA is an open-source data integration and data analysis platform developed by [Bluesquare](https://bluesquarehub.com).

Its goal is to facilitate data integration and analysis workflows, in particular in the context of public health projects.

OpenHEXA allows you to:

1. Create **workspaces** to group code, data and users
2. Upload and read files from a **shared filesystem**
3. Write and read to a PostgreSQL **database**
4. Use Jupyter **notebooks** to explore and analyze data
5. Run and schedule complex data workflows using **data pipelines**
6. Manage your team members

<img width="1363" alt="Workspace homepage" src="https://github.com/BLSQ/openhexa/assets/690667/22a94409-8360-4e69-8a55-c40f71fc5246">

Please note that this repository **does not contain any code**: it is a starting point for OpenHEXA users and implementers. Please refer to the [technical architecture](https://github.com/BLSQ/openhexa/wiki/Technical-architecture) page of our wiki for more information about the different OpenHEXA components, including the links to the relevant GitHub repositories.

## Documentation

The OpenHEXA documentation lives in our [wiki](https://github.com/BLSQ/openhexa/wiki).

To get started, you might be interested in the following pages:

- [User manual](https://github.com/BLSQ/openhexa/wiki/User-manual)
- [Installation instructions](https://github.com/BLSQ/openhexa/wiki/Installation-instructions)

## Roadmap, issues and discussions

Feel free to reach out in the [discussions section](https://github.com/BLSQ/openhexa/discussions) if you have
questions or suggestions!

## Quick Start

Requirements:

- a least [Docker 26.1](https://docs.docker.com/engine/install/debian/#install-using-the-repository)
- Debian bookworm
- Debian packages `gettext-base`, `postgresql` (16+), `postgresql-<postgresql version>-postgis-3`, `duplicity` (optional to manage backup and restore)
- [yq](https://github.com/mikefarah/yq/#install)
- Host port `3100` available for the bundled Forgejo Git server (override with `FORGEJO_PORT`)

After having cloned this repo and change your current dir to it, you can check
your installation by running first

```bash
./script/setup.sh check
```

It'll tell you that the `.env` is missing, that is expected as it's the next
step.

Then, you need to setup the environment and the database. To do so execute the
following command

```bash
./script/setup.sh all
```

This will generate a file in the working directory: `.env` (ee below to
know more about the configuration properties).

Then you can prepare the database and environment with

```bash
./script/openhexa.sh prepare
```

> [!IMPORTANT]
> The `prepare` command will create an initial superuser using the credentials in `.env` (`DJANGO_SUPERUSER_USERNAME` / `DJANGO_SUPERUSER_PASSWORD`). On a fresh install, `setup.sh` auto-generates a random `DJANGO_SUPERUSER_PASSWORD`. Check `.env` to retrieve it for the first login, or edit it before running `prepare` if you want to set your own.

Finally, you can run openhexa with

```bash
./script/openhexa.sh start
```

> [!IMPORTANT]
> The first thing you'll want to do on your running instance is go to the Django admin (on `/admin`). There you can create an "organization" and give your superuser membership to it.

To stop, execute

```bash
./script/openhexa.sh stop
```

If you need to purge the configuration and the database after having stopped it,
you can do it by executing the following command

```bash
./script/setup.sh purge
```

Once installed, it could be interesting to make sure you have the last version.
You can update openhexa with

```bash
./script/openhexa.sh update
```

### Debian Package

#### Requirements

To release and build the Debian package, you need to run on a Debian like Linux distribution
and the following packages are required: `devscripts`, `debhelper`,
`build-essential`. To install them, run the following command:

```bash
sudo apt install devscripts debhelper build-essential
```

Notice this requires super user right (that's what `sudo` gives you).

If you are not on a debian based distribution, you can use the `Dockerfile.build` to build a debian container that will do the job for you.

```bash
docker build --platform linux/amd64 -t openhexa-build -f Dockerfile.build .
docker run -it -v $(pwd):/work openhexa-build
```

You can then follow the instructions below to build the package as usual.

#### Release, changelog, and versions

The versions are described into the [changelog file](debian/changelog). The last
one is unreleased and is the one that is published. To manage versions and
changelog, we use the debhelper tool `dch`.

**Version convention:** the package **upstream version equals the OpenHEXA
app/frontend release it ships** (e.g. `5.10.1`), and must match the
`blsq/openhexa-app` / `blsq/openhexa-frontend` tags in `compose.yml`.

To add a new change, do:

```bash
EMAIL="firstname lastname <email@address.org>" dch -a
```

This will open your favorite editor so you can edit the changelog. Save, commit,
push, and GitHub Actions will do the rest.

To release a version, do:

```bash
EMAIL="firstname lastname <email@address.org>" dch -rD stable
```

To add a new unreleased version do

```bash
EMAIL="firstname lastname <email@address.org>" dch -i -D UNRELEASED -U
```

#### Build

When all the requirements are met, run the following script to build the
package:

```bash
./script/build.sh
```

The script will check the requirements. Notice that it works with your Git
working copy, and all your stage need to be clean. So, if you have any changes,
commit or stash them before running the script.

The resulting package is available in the parent directory:
`../openhexa_5.10.1-1_amd64.deb`.

#### Install

Requirements:

- a least [Docker 26.1](https://docs.docker.com/engine/install/debian/#install-using-the-repository)
- Debian bookworm
- Systemd
- [yq](https://github.com/mikefarah/yq/#install)
- PostgreSQL 16+ (required by OpenHEXA 4.1.0+)
- Host port `3100` free for the bundled Forgejo Git server (override with
  `FORGEJO_PORT` in `/etc/openhexa/env.conf`)

First of all, you need to add our APT repository and GPG public key:

```bash
curl -fsSL https://raw.githubusercontent.com/blsq/openhexa/refs/heads/main/pubkey.gpg | sudo gpg --yes --dearmor --output /usr/share/keyrings/openhexa.gpg
echo "deb [signed-by=/usr/share/keyrings/openhexa.gpg] https://viz.bluesquare.org/openhexa/ bookworm main" | sudo tee /etc/apt/sources.list.d/openhexa.list
```

Make sure your locales are correctly set with `locale`. A common setup is

```
# Set locale
sudo tee -a /etc/default/locale > /dev/null <<EOF
LC_ALL=C.UTF-8
LC_TYPE=C.UTF-8
LC_MESSAGE=C.UTF-8
LC_COLLATE=C.UTF-8
EOF
source /etc/default/locale
```

Then, you can update your APT database and install openhexa

```bash
sudo apt update
sudo apt install openhexa
```

If you want to manage backup and retore through our script, you can install it
with recommended packages `sudo apt install --install-recommends openhexa`.

If you have Systemd, OpenHexa is run as a Systemd service `openhexa` (that you
can then manage with `systemctl`). If you don't use Systemd, you can still run
the service by running `/usr/share/openhexa/openhexa -g start`.

#### Usage

When installed, the Systemd service OpenHexa is started. If you need to get its
status, stop it, restart it, or start it, you can do it with `systemctl`.

A command is also installed to ease the interaction with OpenHexa:
`/usr/share/openhexa/openhexa.sh`. To get its usage documentation, run:

```bash
/usr/share/openhexa/openhexa.sh help
```

If you want to interact with an OpenHexa installed globally on the system,
you'll have to use the option `-g`, or it'll try to interact with the version
in your current directory. For instance, to get its status, you can execute:

```bash
/usr/share/openhexa/openhexa.sh -g status
```

#### Configuration

The installation will also sets up the environment, especially the PostgreSQL
database. The configuration is stored in the file `/etc/openhexa/env.conf`
(see below for more information about the configuration properties). If you
need to change or add, you can directly change this file, then restarts
OpenHexa with `sudo systemctl restart openhexa`.

If you need to set it up again, check the installation, or purge the environment
(database and configuration), you can use the tool
`/usr/share/openhexa/setup.sh`. To get its usage documentation, run:

```bash
/usr/share/openhexa/setup.sh help
```

##### PostgreSQL

During the setup, the following is done on the PostgreSQL side:

- create 2 databases `hexa-app`, and `hexa-hub`. The first one is used by the
  OpenHexa app, the second to manage the notebooks.
- create 1 superuser `hexa-app`, owner of `hexa-app`.
- create 1 superuser `hexa-hub`, owner of `hexa-hub`.
- make PostgreSQL listens on the Docker gateway IP address.
- authorize all users to connect to `hexa-app` from the entire Docker subnetwork
  with encrypted password authentication.
- authorize `hexa-hub` to connect to `hexa-hub` from the entier Docker
  subnetwork with encrypted password authentication.

##### Backup

You can manage your backup and restore directly with OpenHexa. It backs up:

- a `pg_dumpall` of the PostgreSQL cluster (covers the `hexa-app` and
- the workspace files at `WORKSPACE_STORAGE_LOCATION`,
  `hexa-hub` databases),
- the Forgejo data directory at `FORGEJO_STORAGE_LOCATION` (git repositories
  for static webapps plus Forgejo's SQLite metadata database),
- a snapshot of `.env` (so the encryption keys needed to read the restored
  database are kept alongside the data).

This relies on the tool `duplicity`. Make sure that it is installed if you
haven't installed it yet (if you install OpenHexa with `apt`, do it with the
recommended packages).

First, you need to set it up:

```bash
/usr/share/openhexa/setup.sh backup file:///mylocaldirectory/where/to/do/thebackup/ encryption_passkey
```

The target directory will contain two duplicity backends side by side:
`<LOCATION>/workspaces` and `<LOCATION>/forgejo`.

Depending on the user activities, it might be a good idea to stop the service or
simply redirect the website to a maintenance HTML page.

Once configured, the following commands are available:

| Command                                         | Description                                                                              |
| ----------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `/usr/share/openhexa/openhexa.sh backup`        | Back up the PostgreSQL cluster, workspace files, Forgejo data and `.env` snapshot.       |
| `/usr/share/openhexa/openhexa.sh backup-status` | Show the duplicity `collection-status` for both the `workspaces` and `forgejo` backends. |
| `/usr/share/openhexa/openhexa.sh restore`       | Restore the latest backup. This requires stopping the services before a full restore.    |

After a restore, an `openhexa-env.bak` file is left next to the workspace data:
compare it with the live `.env` to make sure `ENCRYPTION_KEY`, `SECRET_KEY` and
the JupyterHub/Forgejo secrets match the restored database.

###### Restoring onto a populated PostgreSQL cluster

`restore` replays a `pg_dumpall` produced without `--clean`, so it expects an empty target cluster (e.g. a fresh install). If the application databases or roles already exist, the `CREATE DATABASE` / `CREATE ROLE` statements will fail, leaving the live data effectively untouched.

To restore on top of an existing setup, drop the application objects manually before running `restore`. Stop the services first so nothing holds open
connections:

```bash
# 1. Stop everything that talks to PostgreSQL.
/usr/share/openhexa/openhexa.sh stop

# 2. Drop the OpenHexa databases and roles as the postgres superuser. Replace
#    the database/role names below with whatever your `.env` defines (typically
#    DATABASE_NAME, JUPYTERHUB_DATABASE_NAME, plus any per-workspace databases
#    matching `[a-z0-9]{16}` that you can list with `\l` in psql).
sudo -u postgres psql -p "$DATABASE_PORT" <<'SQL'
DROP DATABASE IF EXISTS "hexa-app";
DROP DATABASE IF EXISTS "hexa-hub";
-- repeat DROP DATABASE for every workspace database
DROP ROLE IF EXISTS "hexa-app";
DROP ROLE IF EXISTS "hexa-hub";
-- repeat DROP ROLE for every workspace role
SQL

# 3. Now run the restore.
/usr/share/openhexa/openhexa.sh restore
```

###### Restoring a pre-Forgejo backup (legacy layout)

Backups taken before the Forgejo upgrade used a single duplicity backend at
`<LOCATION>` (no `workspaces` / `forgejo` sub-prefix) and did not include a
Forgejo data directory or an `.env` snapshot. `openhexa.sh restore` won't
recover them as-is — it expects both new sub-prefixes to exist. Restore them
by hand with `duplicity`:

```bash
# Stop the services first
sudo systemctl stop openhexa

# Restore the workspace tree (includes the legacy openhexa-dumpall.sql)
sudo -u openhexa PASSPHRASE='your-passphrase' duplicity restore \
    file:///path/to/old/backup/ \
    /var/lib/openhexa/workspaces

# Load the PostgreSQL dump
sudo -u postgres psql -f /var/lib/openhexa/workspaces/openhexa-dumpall.sql template1

# Forgejo had no data in the legacy layout: leave FORGEJO_STORAGE_LOCATION
# empty and let `openhexa.sh prepare` bootstrap a fresh Forgejo on next start.
sudo systemctl start openhexa
/usr/share/openhexa/openhexa.sh prepare
```

#### Configuration properties

##### The storage engine

Locally, we use Minio to manage the storage. It provides a AWS S3 compatible
API. To access to it, you need to provide a key Id and a secret:
`WORKSPACE_STORAGE_ENGINE_AWS_ACCESS_KEY_ID` and
`WORKSPACE_STORAGE_ENGINE_AWS_SECRET_ACCESS_KEY`.

Finally, we need the port number where the local PostgreSQL cluster listens:
`DB_PORT`

##### Email server

In order to be able to send mails to users, you have to provide the configuration options:

- `EMAIL_HOST`
- `EMAIL_PORT`
- `EMAIL_HOST_USER`
- `EMAIL_USE_TLS`
- `EMAIL_USE_SSL`
- `EMAIL_HOST_PASSWORD`
- `DEFAULT_FROM_EMAIL`

##### Database connection credentials

The `workspace.db` proxy host doesn't work on local installations of OpenHEXA.
You can override it by setting this ENV variable to the local IP of the server:

```
OVERRIDE_WORKSPACES_DATABASE_HOST="<LOCAL-IP>"
```

##### Forgejo Git server

Since OpenHEXA 5.0.0, the Static Webapps feature is backed by a Forgejo Git
server that runs as a sibling container. The package ships a `forgejo`
service (image `codeberg.org/forgejo/forgejo:14`) and a custom entrypoint
at `/usr/share/openhexa/forgejo/entrypoint.sh` that creates the admin user
on first boot.

The relevant configuration properties:

- `GIT_SERVER_ADMIN_USERNAME` (default `openhexa-admin`)
- `GIT_SERVER_ADMIN_PASSWORD`: auto-generated by `setup.sh` on first install
- `FORGEJO_PORT` (default `3100`): host port mapped to the Forgejo UI

The Django backend talks to Forgejo over the internal Docker network at
`http://forgejo:3000`. This is set in `compose.yml` and does not require
configuration. Forgejo's data lives in the named Docker volume
`forgejo_data` and is preserved across `update`/`restart`.

##### Static Webapps subdomain (optional)

Set `WEBAPPS_DOMAIN=webapps.example.com` to serve each public webapp from
its own subdomain (e.g. `app1.webapps.example.com`). This requires a
wildcard DNS record pointing at this host. Leave the variable empty to keep
webapps on the main backend host.

For custom-domain webapps, list each domain in `ADDITIONAL_ALLOWED_HOSTS`
_and_ attach it to the corresponding Webapp via the Django admin.

#### Upgrading an existing installation

Upgrading an existing installation may require manual steps such as adding new environment
variables, infrastructure changes, and one-off migration commands.
These are documented per version, newest first, in [UPGRADING.md](./UPGRADING.md).

> [!IMPORTANT]
> `setup.sh` only generates `.env` on a **fresh** install, so new variables
> added to `.env.dist` are not propagated to an existing `.env`. Always check
> [UPGRADING.md](./UPGRADING.md) for the variables introduced since your
> installed version before starting the upgraded stack.

#### Test

To test if OpenHexa has been correctly installed, you can run smoke tests that
will check minimum operation. To learn how to do so, please read its
[dedicated README](./smoke-tests/README.md).

#### CI

We use Github Actions to automate the package building and its tests. If you
want to run our workflows locally, you can use [`act`](https://nektosact.com/)
as it follows:

```bash
act --action-offline-mode push
```

Warning: Make sure to remove your local `.env` before running it as `act` copies your working copy rather than using the checking out action. When it
happens, it overrides other environment files that are provided to the compose
project, which is used to configure it (`/etc/openhexa/env.conf`).

##### The storage engine

Locally, we use Minio to manage the storage. It provides a AWS S3 compatible
API. To access to it, you need to provide a key Id and a secret:
`WORKSPACE_STORAGE_ENGINE_AWS_ACCESS_KEY_ID` and
`WORKSPACE_STORAGE_ENGINE_AWS_SECRET_ACCESS_KEY`.

Finally, we need the port number where the local PostgreSQL cluster listens:
`DB_PORT`

#### Publish OpenHexa through a NGINX proxy

##### Without TLS/SSL

The following requires you the following:

- a machine with a public IP address,
- a domain name for which you manage the zone,
- the NGINX service,

Create a file `/etc/nginx/sites-available/openhexa` with the following content
(replace `example.com` with your domain name):

```
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80;
    server_name example.com;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    location ~ ^/(?<root_path>hub|user)(?<path>/.*)? {
        rewrite ^ /$root_path$path break;
        proxy_pass http://localhost:8001;

        # websocket headers
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header X-Scheme $scheme;

        proxy_buffering off;
    }

    # Static Webapps auth-token endpoint is served by the backend (app),
    # not the frontend, so route it directly to the backend port.
    location /webapps/ {
        proxy_pass http://localhost:8000;
    }


    location / {
        proxy_pass http://localhost:3000;
    }

}

# Support for webapps wildcard host:
# Route all *.webapps.example.com subdomains (e.g. my-app.webapps.example.com) to the backend on port 8000.
server {
    listen 80;
    client_max_body_size 500M;
    server_name *.webapps.example.com;

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Enable and check it:

```bash
sudo ln -s /etc/nginx/sites-available/openhexa /etc/nginx/sites-enabled/
sudo nginx -t
```

You need to update on OpenHexa config in `/etc/openhexa/env.conf`:

```bash
TRUST_FORWARDED_PROTO="false"
PROXY_HOSTNAME_AND_PORT=example.com
INTERNAL_BASE_URL=http://app:8000
APP_PORT=8000
FRONTEND_PORT=3000
JUPYTERHUB_PORT=8001
```

Finally, restart NGINX and OpenHexa:

```bash
sudo systemctl restart openhexa nginx
```

You can browse now OpenHexa app at `http://example.com`.

##### With TLS/SSL

Additionnaly, you need a certificate. The way it has been retrieved is up to the reader. For the rest, follow the same playbook, except to use the following
config

in `/etc/nginx/sites-available/openhexa`:

```
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80;
    server_name example.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl;
    server_name example.com;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    ssl_certificate /etc/ssl/certs/nginx-selfsigned.crt;
    ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;
    ssl_protocols TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers EECDH+AESGCM:EDH+AESGCM;
    ssl_ecdh_curve secp384r1;
    ssl_session_timeout  10m;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";
    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";

    location ~ ^/(?<root_path>hub|user)(?<path>/.*)? {
        rewrite ^ /$root_path$path break;
        proxy_pass http://localhost:8001;

        # websocket headers
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header X-Scheme $scheme;

        proxy_buffering off;
    }

    # Static Webapps auth-token endpoint is served by the backend (app),
    # not the frontend, so route it directly to the backend port.
    location /webapps/ {
        proxy_pass http://localhost:8000;
    }


    location / {
        proxy_pass http://localhost:3000;
    }

}

# Support for webapps wildcard host:
# Route all *.webapps.example.com subdomains (e.g. my-app.webapps.example.com) to the backend on port 8000.
server {
    client_max_body_size 500M;
    server_name *.webapps.example.com;

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    listen 443 ssl;
    ssl_certificate /etc/ssl/certs/nginx-selfsigned.crt;
    ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;
}


server {
    listen 80;
    server_name *.webapps.example.com;
    return 301 https://$host$request_uri;
}
```

and in `/etc/openhexa/env.conf`

```bash
TRUST_FORWARDED_PROTO="true"
PROXY_HOSTNAME_AND_PORT=example.com
INTERNAL_BASE_URL=http://app:8000
APP_PORT=8000
FRONTEND_PORT=3000
JUPYTERHUB_PORT=8001
```
