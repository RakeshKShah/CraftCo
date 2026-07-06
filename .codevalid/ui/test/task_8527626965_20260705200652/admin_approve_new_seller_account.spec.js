import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../helpers/execution-recorder.js";
import { setupAuthMocks, setupAdminMocks, setupMarketplaceMocks } from "../helpers/mock-api.js";

test("Admin approves a new seller account", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder("admin_approve_new_seller_account", "Admin approves a new seller account");

  const sellers = [
    {
      id: "seller-pending-1",
      email: "newmaker@example.com",
      store_name: "New Maker Studio",
      status: "PENDING",
      product_count: 0,
    },
  ];

  await setupAuthMocks(page, {
    me: {
      id: "admin-1",
      email: "admin@example.com",
      role: "ADMIN",
      status: "ACTIVE",
    },
    token: "admin-token",
  });
  await setupAdminMocks(page, { sellers, products: [] });
  await setupMarketplaceMocks(page, { products: [] });

  await recorder.step(page, "Open the AdminPage", async () => {
    await page.addInitScript(() => {
      window.localStorage.setItem("token", "admin-token");
    });
    // Navigate to "/" first so auth loads before we hit the protected /admin route.
    await page.goto("/");
    await expect(page.getByText("admin@example.com")).toBeVisible();
    await page.getByRole("link", { name: "Admin" }).click();
    await expect(page.getByRole("heading", { name: "Admin panel" })).toBeVisible();
  });

  await recorder.step(page, "Locate a seller account that is pending approval", async () => {
    const row = page.locator("tbody tr").filter({ hasText: "New Maker Studio" });
    await expect(row).toContainText("PENDING");
    await expect(row.getByRole("button", { name: "Approve" })).toBeVisible();
  });

  await recorder.step(page, "Perform the approval action for the seller account", async () => {
    const row = page.locator("tbody tr").filter({ hasText: "New Maker Studio" });
    await row.getByRole("button", { name: "Approve" }).click();
    await expect(row).toContainText("ACTIVE");
  });

  await recorder.step(page, "Refresh or revisit the seller account information", async () => {
    // Simulate a refresh: navigate away and back via soft navigation to avoid auth race.
    await page.goto("/");
    await expect(page.getByText("admin@example.com")).toBeVisible();
    await page.getByRole("link", { name: "Admin" }).click();
    await expect(page.getByRole("heading", { name: "Admin panel" })).toBeVisible();
    const row = page.locator("tbody tr").filter({ hasText: "New Maker Studio" });
    await expect(row).toContainText("ACTIVE");
    await expect(row.getByRole("button", { name: "Suspend" })).toBeVisible();
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:admin_approve_new_seller_account");
  await recorder.save(testInfo);
});
