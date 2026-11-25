# Prepares a new install for the openhexa-app e2e suite: the account it signs
# in as, an organization and a workspace owned by it, and a pipeline template
# to create pipelines from. Used by the `e2e` job
# of .github/workflows/build_debian_package.yml, on an install that is thrown
# away afterwards, so it is not meant to be run twice.
#
# It runs inside the backend and takes everything from the environment:
#
#   docker exec -i -e E2E_EMAIL -e E2E_PASSWORD -e E2E_ORGANIZATION_NAME \
#     -e E2E_ORGANIZATION_SHORT_NAME -e E2E_WORKSPACE_NAME \
#     app python manage.py shell < e2e/seed.py
#
# It prints what the suite and the loading of its sample tables need next:
# E2E_ORGANIZATION_ID, E2E_WORKSPACE_SLUG and WORKSPACE_DATABASE_URL.

import io
import os
import zipfile

from hexa.pipelines.models import Pipeline
from hexa.user_management.models import (
    Organization,
    OrganizationMembership,
    OrganizationMembershipRole,
    OrganizationType,
    User,
)
from hexa.workspaces.models import Workspace

# An ordinary account rather than the superuser, which sees every organization.
user = User.objects.create_user(
    email=os.environ["E2E_EMAIL"], password=os.environ["E2E_PASSWORD"]
)

organization = Organization.objects.create(
    name=os.environ["E2E_ORGANIZATION_NAME"],
    short_name=os.environ["E2E_ORGANIZATION_SHORT_NAME"],
    organization_type=OrganizationType.CORPORATE,
)
OrganizationMembership.objects.create(
    organization=organization, user=user, role=OrganizationMembershipRole.OWNER
)

# Creates the workspace's database and bucket too, and makes the account an
# admin of it.
workspace = Workspace.objects.create_if_has_perm(
    user, name=os.environ["E2E_WORKSPACE_NAME"], organization=organization
)

# A new install has no pipeline template, and the suite creates pipelines from
# the first one of the catalogue. Its source pipeline lives in a workspace of
# its own, as the suite expects to find its workspace empty.
TEMPLATE_SOURCE = '''from openhexa.sdk import current_run, pipeline


@pipeline("e2e_template", name="E2E template")
def e2e_template():
    current_run.log_info("Created from the E2E template")


if __name__ == "__main__":
    e2e_template()
'''
archive = io.BytesIO()
with zipfile.ZipFile(archive, "w") as zip_file:
    zip_file.writestr("pipeline.py", TEMPLATE_SOURCE)

templates_workspace = Workspace.objects.create_if_has_perm(
    user, name="Pipeline templates", organization=organization
)
source = Pipeline.objects.create_if_has_perm(
    user, templates_workspace, name="E2E template"
)
version = source.upload_new_version(
    user, parameters=[], name="v1", zipfile=archive.getvalue()
)
template, _ = source.get_or_create_template(
    name="E2E template",
    code="e2e-template",
    description="A pipeline that logs one message.",
)
template.create_version(version, user=user, name="v1", changelog="First version")

print(f"E2E_ORGANIZATION_ID={organization.id}")
print(f"E2E_WORKSPACE_SLUG={workspace.slug}")
print(f"WORKSPACE_DATABASE_URL={workspace.db_url}")
