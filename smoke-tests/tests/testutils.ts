import { test as base, expect, Page} from '@playwright/test';

export async function login(page) {
  // Login
  await page.goto("/login");
  await page.getByPlaceholder('Email address').fill(process.env.OPENHEXA_USERNAME);
  await page.getByPlaceholder('Password').fill(process.env.OPENHEXA_PASSWORD);
  await page.getByRole('button', {name: "Sign in"}).click({ force: true });
  await page.waitForNavigation();
  expect(page.url().startsWith('/login')).toBeFalsy();
}

export const test = base.extend<{workspacePage: Page}>({
  workspacePage: async ({ page }, use) => {
    await login(page)
    await use(page)
  },
})