import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../helpers/execution-recorder.js";
import { setupAuthMocks, setupAdminMocks, setupMarketplaceMocks } from "../helpers/mock-api.js";

test("Suspended seller listings remain visible in admin panel", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder("suspended_seller_listings_visible_in_admin_panel", "Suspended seller listings remain visible in admin panel");

  const sellers = [
    {
      id: "seller-suspended-1",
      email: "hidden@example.com",
      store_name: "Hidden Craft House",
      status: "SUSPENDED",
      product_count: 1,
    },
  ];

  const products = [
    {
      id: "prod-hidden-1",
      title: "Suspended Seller Candle",
      category: "home",
      price_cents: 2600,
      stock_qty: 4,
      status: "ACTIVE",
      visible: false,
      store_name: "Hidden Craft House",
      seller_status: "SUSPENDED",
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
    await page.goto("/admin");
    await expect(page.getByRole("heading", { name: "Admin panel" })).toBeVisible();
  });

  await recorder.step(page, "Navigate to the suspended seller account details or associated listings view", async () => {
    await expect(page.getByRole("heading", { name: "All listings" })).toBeVisible();
    await expect(page.getByText("Includes hidden listings from suspended sellers (BR-04)")).toBeVisible();
  });

  await recorder.step(page, "Observe the seller's listings", async () => {
    const row = page.locator("tbody tr").filter({ hasText: "Suspended Seller Candle" });
    await expect(row).toContainText("Hidden Craft House");
    await expect(row).toContainText("SUSPENDED");
    await expect(row).toContainText("No");
    await expect(row.getByRole("button", { name: "Remove" })).toBeVisible();
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:suspended_seller_listings_visible_in_admin_panel");
  await recorder.save(testInfo);
});
