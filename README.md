<div align="center">
   <img alt="OpenHEXA Logo" src="https://raw.githubusercontent.com/BLSQ/openhexa-app/main/backend/hexa/static/img/logo/logo_with_text_black.svg" height="80">
</div>
<p align="center">
    <em>Open-source data integration and analysis platform</em>
</p>

[![build_debian_package](https://github.com/BLSQ/openhexa/actions/workflows/build_debian_package.yml/badge.svg)](https://github.com/BLSQ/openhexa/actions/workflows/build_debian_package.yml)

OpenHEXA
========

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

Documentation
-------------

The OpenHEXA documentation lives in our [wiki](https://github.com/BLSQ/openhexa/wiki).

To get started, you might be interested in the following pages:

- [User manual](https://github.com/BLSQ/openhexa/wiki/User-manual)
- [Installation instructions](https://github.com/BLSQ/openhexa/wiki/Installation-instructions)

Roadmap, issues and discussions
-------------------------------

You can find the public roadmap [here](https://github.com/orgs/BLSQ/projects/3).

Please report bugs in the issues section of this repository: https://github.com/BLSQ/openhexa/main/issues.

Feel free to reach out in the [discussions section](https://github.com/BLSQ/openhexa/discussions) if you have 
questions or suggestions!

Quick Start
-----------

Requirements:
- a least [Docker 26.1](https://docs.docker.com/engine/install/debian/#install-using-the-repository)
- Debian bookworm
- Debian packages `gettext-base`, `postgresql` (14+), `postgresql-<postgresql version>-postgis-3`, `duplicity` (optional to manage backup and restore)
- [yq](https://github.com/mikefarah/yq/#install)

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

Finally, you can run openhexa with

```bash
./script/openhexa.sh start
```

To stop, execute

```bash
./script/openhexa.sh stop
```

If you need to purge the configuration and the database after having stopped it,
you can do it by executing the following command

```bash
./script/openhexa.sh purge
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

The versions are described into  the [changelog file](debian/changelog). The last
one is unreleased and is the one that is published. To manage versions and
changelog, we use the debhelper tool `dch`.

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
`../openhexa_1.0-1_amd64.deb`.

#### Install

Requirements:
- a least [Docker 26.1](https://docs.docker.com/engine/install/debian/#install-using-the-repository)
- Debian bookworm
- Systemd
- [yq](https://github.com/mikefarah/yq/#install)

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

You can manage your backup and restore directly with OpenHexa. It will backup
all the workspaces data, and all databases. This relies on the tool `duplicity`.
Make sure that it is installed if you haven't installed it yet (if you install
OpenHexa with `apt`, do it with the recommended packages).

First, you need to set it up:

```bash
/usr/share/openhexa/setup.sh backup /mylocaldirecotry/where/to/do/thebackup/ encryption_passkey
```

Then you can back up the data with:

```bash
/usr/share/openhexa/openhexa.sh backup
```

Depending on the user activities, it might be a good idea to stop the service or
simply redirect the website to a maintenance HTML page.

To restore the data, you execute the following:

```bash
/usr/share/openhexa/openhexa.sh backup
```

In this case, we advise you to stop the service before performing a full
restore.

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


    location / {
        proxy_pass http://localhost:3000;
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


    location / {
        proxy_pass http://localhost:3000;
    }

}
```

and in `/etc/openhexa/env.conf`

```bash
TRUST_FORWARDED_PROTO="true"
PROXY_HOSTNAME_AND_PORT=example.com
INTERNAL_BASE_URL=http://app:8000
FRONTEND_PORT=3000
JUPYTERHUB_PORT=8001
```
