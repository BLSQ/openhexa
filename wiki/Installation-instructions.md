# OpenHexa installation instructions

The OpenHexa platform is composed of multiple components, each having it own
repository: 

- [BLSQ/openhexa-app](https://github.com/BLSQ/openhexa-app): the
  **App component** (Django app for business logic & API)
- [BLSQ/openhexa-frontend](https://github.com/BLSQ/openhexa-frontend): the
  **Frontend component**, a React/NextJS application
- [BLSQ/openhexa-notebooks](https://github.com/BLSQ/openhexa-notebooks): the
  **Notebooks component**, a customized [JupyterHub](https://jupyter.org/hub)
  setup

Notice, there is one more component, that is deprecated: the
**Pipelines component**
([BLSQ/openhexa-pipelines](https://github.com/BLSQ/openhexa-pipelines)). It's a
series of data pipelines running on [Airflow](https://airflow.apache.org/).

The recommended way to deploy OpenHexa is to use
[Kubernetes](http://kubernetes.io/). For a local development install, we
recommend to use Docker.

## Development installation

As each component requires a different stack, for local development, we
recommend to use Docker. We provide Docker Compose manifest to deploy OpenHexa
apps and Notebooks. As for the frontend, it requires a Node local environment
to be directly run.

In brief, when the 3 components Git repositories have been locally cloned, you
can run them in order:

1. the app with the pipelines runner and scheduler,
2. the notebook, then
3. the frontend.

You'll find detailed instructions for local development in each component README:

* [app](https://github.com/BLSQ/openhexa-app/blob/main/README.md#local-development),
* [frontend](https://github.com/BLSQ/openhexa-frontend#local-development), and
* [notebook](https://github.com/BLSQ/openhexa-notebooks#local-development).

Even if the component is containerized, changing your local working copy will be
taken in account.

Below, you'll find a short version to setup quickly a development environment
for OpenHexa:

### Requirements

* [Docker Engine](https://docs.docker.com/engine/install/)
* [Node.js Version Manager](https://github.com/nvm-sh/nvm#install--update-script)

### App

```bash
git clone git@github.com:BLSQ/openhexa-app.git
cp .env.dist .env
# edit the .env file to configure your instance
docker network create openhexa
docker compose build
docker compose run app fixtures
docker compose run app manage tailwind install
docker compose run app manage tailwind build
docker compose up --profile pipelines
```

Two URL endpoints are now exposed locally on the port `8000`:

* `http://localhost:8000/graphql` for the GraphQL API
* `http://localhost:8000/ready` for the readiness endpoint

### Notebooks

```bash
git clone git@github.com:BLSQ/openhexa-notebooks.git
docker compose -f docker-compose.yml -f docker-compose-withdockerhub.yml up
```

### Frontend

```bash
git clone git@github.com:BLSQ/openhexa-frontend.git
npm install
cp .env.local.dist .env.local
# edit the .env file to configure your instance
npm run dev
```

The web app is then served locally on the port `3000`. You can browse and login
at `http://localhost:3000`. The default credentials are
`root@openhexa.org`/`root`.

## Deploying OpenHexa

[Kubernetes](https://kubernetes.io/) is the recommended way to deploy OpenHexa.

### Pre-requisites

To deploy OpenHexa, you will need:

- A [Kubernetes](https://kubernetes.io/) cluster
- A [PostgreSQL](https://www.postgresql.org/) server
- A way to provision object storage, such as AWS S3, Google Cloud GCS, or an open-source equivalent

### Deployment

🚧 For now, the different components must be installed separately. We are currently working on a [Helm](https://helm.sh/) chart that will facilitate the deployment of OpenHexa. In the meantime, you will find below a high-level overview of how OpenHexa is deployed on a Kubernetes cluster. Don't hesitate to [reach out](https://github.com/BLSQ/openhexa/discussions) if you need assistance with an OpenHexa deployment.

#### App deployment

The [openhexa-app](https://github.com/BLSQ/openhexa-app) component is a rather standard [Django](https://www.djangoproject.com/) application. Deploying it with Kubernetes consists in:

1. Creating a Kubernetes `Deployment`, a `Service` and exposing it with an `Ingress`
1. Creating a `Deployment` resources for the `datasources_worker` command
1. Creating `CronJob` in Kubernetes for the `environment_sync` and `datasource_sync` commands
1. Creating a `Secret` and a `ConfigMap` for the values required by the app component (see `settings.py` for the parameter reference)

#### Frontend deployment

The [openhexa-frontend](https://github.com/BLSQ/openhexa-frontend) component is a [NextJS](https://nextjs.org/) React application. Deploying it with Kubernetes consists in:

1. Creating a Kubernetes `Deployment`, a `Service` and exposing it with an `Ingress`
1. Creating a `Secret` and a `ConfigMap` for the values required by the app component (see `.env.local.dist` for the parameter reference)

#### Notebooks deployment

The recommended way to deploy the OpenHexa notebooks component is to use the Helm Chart provided by the [Zero To Kubernetes](https://zero-to-jupyterhub.readthedocs.io/en/latest/) project.

#### Pipelines deployment

The recommended way to deploy the OpenHexa pipeline component is to use the Helm Chart provided by [Airflow](https://airflow.apache.org/docs/helm-chart/stable/index.html).