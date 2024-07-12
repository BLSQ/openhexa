import { test } from '@playwright/test';
import { login } from './testutils';

const graphql = async (page, query, variables?: any) => {
  const response = await page.request.fetch(`${process.env.OPENHEXA_BASE_URL}/graphql/`, {
    method: "POST",
    failOnStatusCode: true,
    headers: {
      "Content-Type": "application/json",
    },
    data: {
      query, variables
    }
  })
  return await response.json()
}

test('create new workspace if needed', async ({ page }) => {
  await login(page)

  const workspacesPayload = await graphql(page, `query Workspaces {
    workspaces(page: 1) { items { slug } }
  }`)
  if (workspacesPayload.data.workspaces.items.length === 0) {
    // Create a workspace
    await graphql(page, `mutation createWorkspace($input: CreateWorkspaceInput!) {
      createWorkspace(input: $input) {
        success
        errors
        workspace {
          slug
          name
        }
      }
    }`, {
      input: {
        name: "Smoke tests",
        loadSampleData: true
      }
    })
  }
});