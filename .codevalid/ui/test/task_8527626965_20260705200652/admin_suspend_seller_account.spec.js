import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../helpers/execution-recorder.js";
import { setupAuthMocks, setupAdminMocks, setupMarketplaceMocks } from "../helpers/mock-api.js";

test("Admin suspends a seller account", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder("admin_suspend_seller_account", "Admin suspends a seller account");

  const sellers = [
    {
      id: "seller-active-1",
      email: "maker@example.com",
      store_name: "Studio Earth",
      status: "ACTIVE",
      product_count: 2,
    },
  ];

  const products = [
    {
      id: "prod-1",
      title: "River Vase",
      category: "ceramics",
      price_cents: 5200,
      stock_qty: 3,
      status: "ACTIVE",
      visible: true,
      store_name: "Studio Earth",
      seller_status: "ACTIVE",
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
  await setupAdminMocks(page, { sellers, products });
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

  await recorder.step(page, "Locate an active seller account", async () => {
    const row = page.locator("tbody tr").filter({ hasText: "Studio Earth" }).first();
    await expect(row).toContainText("ACTIVE");
    await expect(row.getByRole("button", { name: "Suspend" })).toBeVisible();
  });

  await recorder.step(page, "Perform the suspension action for the seller account", async () => {
    const row = page.locator("tbody tr").filter({ hasText: "Studio Earth" }).first();
    await row.getByRole("button", { name: "Suspend" }).click();
    await expect(row).toContainText("SUSPENDED");
  });

  await recorder.step(page, "Refresh or revisit the seller account information", async () => {
    // Simulate a refresh: navigate away and back via soft navigation to avoid auth race.
    await page.goto("/");
    await expect(page.getByText("admin@example.com")).toBeVisible();
    await page.getByRole("link", { name: "Admin" }).click();
    await expect(page.getByRole("heading", { name: "Admin panel" })).toBeVisible();
    const row = page.locator("tbody tr").filter({ hasText: "Studio Earth" }).first();
    await expect(row).toContainText("SUSPENDED");
    await expect(row.getByRole("button", { name: "Approve" })).toBeVisible();
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:admin_suspend_seller_account");
  await recorder.save(testInfo);
});
