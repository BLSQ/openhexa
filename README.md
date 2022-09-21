<div align="center">
   <img alt="OpenHexa Logo" src="https://raw.githubusercontent.com/BLSQ/openhexa-app/main/hexa/static/img/logo/logo_with_text_grey.svg" height="80">
</div>
<p align="center">
    <em>Open-source Data integration platform</em>
</p>
<p align="center">
   <a href="https://github.com/BLSQ/openhexa-app/actions/workflows/test.yml">
      <img alt="Test Suite" src="https://github.com/BLSQ/openhexa-app/actions/workflows/test.yml/badge.svg">
   </a>
</p>

OpenHexa
========

OpenHexa is an **open-source data integration platform** that allows users to:

- Explore data coming from a variety of sources in a **data catalog**
- Schedule **data pipelines** for extraction & transformation operations
- Perform data analysis in **notebooks**
- Create rich data **visualizations**

<div align="center">
   <img alt="OpenHexa Screenshot" src="https://test.openhexa.org/img/screenshot_catalog.png" hspace="10" height="150">
   <img alt="OpenHexa Screenshot" src="https://test.openhexa.org/img/screenshot_notebook.png" hspace="10" height="150">
</div>

This repository **does not contain any code**: it is a starting point for OpenHexa users and implementers.

Roadmap and issues
==================

You can find the publid roadmap [https://github.com/orgs/BLSQ/projects/3](here).

Please report bugs in the issues section of this repository: https://github.com/BLSQ/openhexa/issues.

OpenHexa architecture
=====================

The OpenHexa platform is composed of **four main components**:

- The [App component](https://github.com/BLSQ/openhexa-app), a Django application that contains most of the OpenHexa business logic as well as a GraphQL API used by the other components
- The [Frontend component](https://github.com/BLSQ/openhexa-frontend), a React/NextJS application that contains the user-facing part of OpenHexa
- The [Notebooks component](https://github.com/BLSQ/openhexa-notebooks), a customized [JupyterHub](https://jupyter.org/hub) setup
- The [Pipelines component](https://github.com/BLSQ/openhexa-pipelines) a series of Pipelines running on [Airflow](https://airflow.apache.org/)

Please refer to the component-specific documentation in the above repositories if you need more details regarding the technical implementation.

Deploying OpenHexa
==================

Our recommendation for the deployment of a dedicated OpenHexa instance would be to use [Kubernetes](https://kubernetes.io/fr/).

We are currently in the process of writing detailed deployment documentation using Kubernetes, as well as open-sourcing a [Helm](https://helm.sh/) chart to facilitate deployments.
