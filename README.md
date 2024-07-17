<div align="center">
   <img alt="OpenHEXA Logo" src="https://raw.githubusercontent.com/BLSQ/openhexa-app/main/hexa/static/img/logo/logo_with_text_grey.svg" height="80">
</div>
<p align="center">
    <em>Open-source Data integration platform</em>
</p>

[![build_debian_package](https://github.com/BLSQ/openhexa/actions/workflows/build_debian_package.yml/badge.svg)](https://github.com/BLSQ/openhexa/actions/workflows/build_debian_package.yml)

OpenHEXA
========

OpenHEXA is an open-source data integration platform developed by [Bluesquare](https://bluesquarehub.com).

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
- a least docker 26.1
- Debian bookworm
- Debian packages `gettext-base` `postgresql` `postgresql-14-postgis-3`
- [yq](https://github.com/mikefarah/yq/#install)

You can check your installation by running first

```bash
./script/setup check
```

It'll tell you that the `.env` is missing, that is expected as it's the next
step.

Then, you need to setup the environment and the database. To do so execute the
following command

```bash
./script/setup env
./script/setup db
```

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

### Debian Package

#### Build

To build the Debian package, you need to run on a Debian like Linux distribution
and the following packages are required: `devscripts`, `debhelper`,
`build-essential`. To install them, run the following command:

```bash
sudo apt install devscripts debhelper build-essential
```

Notice this requires super user right (that's what `sudo` gives you).

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
- a least docker 26.1
- Debian bookworm
- Debian packages `gettext-base`, `openssl`, `postgresql`,
  `postgresql-14-postgis-3`
- [yq](https://github.com/mikefarah/yq/#install)

You can install OpenHexa on your system and run it as a Systemd service
`openhexa` (that you can then manage with `systemctl`). Run the following
command:

```bash
sudo dpkg -i openhexa_1.0-1.deb
```

Notice this requires super user right (that's what `sudo` gives you).

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
database. The configuration is stored in the file `/etc/openhexa/env.conf`. If
you need to change or add, you can directly change this file, then restarts
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
