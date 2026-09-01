import { expect, test } from "@playwright/test";
import { login } from "./testutils";

const graphql = async (page, query, variables?: any) => {
  const response = await page.request.fetch(
    `${process.env.OPENHEXA_BASE_URL}/graphql/`,
    {
      method: "POST",
      failOnStatusCode: true,
      headers: {
        "Content-Type": "application/json",
      },
      data: {
        query,
        variables,
      },
    },
  );
  const payload = await response.json();
  // GraphQL answers with a 200 status even when the query is rejected, so
  // `failOnStatusCode` above never catches those. Without this check a broken
  // setup stays green and every test that needs a workspace fails instead.
  if (payload.errors) {
    throw new Error(
      `GraphQL request failed: ${JSON.stringify(payload.errors)}`,
    );
  }
  return payload;
};

// It logs in the user and check if a workspace exists, if not, it creates one with sample data
test("create new workspace if needed", async ({ page }) => {
  await login(page);
  const workspacesPayload = await graphql(
    page,
    `
      query Workspaces {
        workspaces(page: 1) {
          items {
            slug
          }
        }
      }
    `,
  );
  if (workspacesPayload.data.workspaces.items.length > 0) {
    return;
  }

  // Since OpenHEXA 5.14.0 a workspace always belongs to an organization and
  // `CreateWorkspaceInput.organizationId` is mandatory.
  const organizationsPayload = await graphql(
    page,
    `
      query Organizations {
        organizations {
          id
          name
          permissions {
            createWorkspace {
              isAllowed
            }
          }
        }
      }
    `,
  );
  const organizations = organizationsPayload.data.organizations;
  const organization = organizations.find(
    (candidate) => candidate.permissions.createWorkspace.isAllowed,
  );
  if (!organization) {
    throw new Error(
      `Cannot create a workspace: none of the ${organizations.length} organization(s) available to this user allow it.`,
    );
  }

  // Create a workspace
  const createWorkspacePayload = await graphql(
    page,
    `
      mutation createWorkspace($input: CreateWorkspaceInput!) {
        createWorkspace(input: $input) {
          success
          errors
          workspace {
            slug
            name
          }
        }
      }
    `,
    {
      input: {
        name: "Smoke tests",
        organizationId: organization.id,
        loadSampleData: true,
      },
    },
  );
  expect(createWorkspacePayload.data.createWorkspace.errors).toEqual([]);
  expect(createWorkspacePayload.data.createWorkspace.success).toBeTruthy();
});
