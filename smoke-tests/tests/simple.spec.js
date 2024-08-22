// @ts-check

import { expect } from "@playwright/test";
import { test } from "./testutils";

test("is web ready?", async ({ page }) => {
  await page.goto("/ready");
  await expect(page.getByText("ok")).toBeVisible();
});

test.describe("it can view a workspace's common pages", () => {
  test("view workspace's dashboard", async ({ page, workspacePage }) => {
    page.on('console', msg => {
      if (msg.type() === 'error')
        console.log(`Error text: "${msg.text()}"`);
    });
    await expect(
      workspacePage.getByText(/Where to go from here?/),
    ).toBeVisible();
  });

  test("view workspace's tables", async ({ workspacePage }) => {
    await workspacePage
      .getByRole("navigation")
      .getByRole("link")
      .nth(2)
      .click(); // Tables link
    await expect(
      workspacePage.getByRole("heading", { name: "Tables" }),
    ).toBeVisible();
    await expect(
      workspacePage.getByRole("columnheader", { name: "Name" }).first(),
    ).toBeVisible();
  });

  test("view workspace's files", async ({ workspacePage }) => {
    await workspacePage
      .getByRole("navigation")
      .getByRole("link")
      .nth(1)
      .click(); // Files link
    await expect(
      workspacePage.getByRole("columnheader", { name: "Size" }).first(),
    ).toBeVisible();
    await expect(
      workspacePage.getByRole("columnheader", { name: "Name" }).first(),
    ).toBeVisible();
  });

  test("view workspace's jupyterlab environment", async ({ workspacePage }) => {
    await workspacePage
      .getByRole("navigation")
      .getByRole("link")
      .nth(6)
      .click(); // Jupyterlab link
    await expect(
      await workspacePage
        .frameLocator("iframe")
        .getByRole("heading", { name: "Notebook" }),
    ).toBeVisible({ timeout: 60000 });
  });
});
