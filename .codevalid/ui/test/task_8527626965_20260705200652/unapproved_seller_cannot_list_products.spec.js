import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../helpers/execution-recorder.js";
import { setupAuthMocks, setupSellerDashboardMocks, setupMarketplaceMocks } from "../helpers/mock-api.js";

test("Unapproved seller cannot list products", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder("unapproved_seller_cannot_list_products", "Unapproved seller cannot list products");

  await setupAuthMocks(page, {
    me: {
      id: "seller-1",
      email: "pending@example.com",
      role: "SELLER",
      status: "PENDING",
    },
    token: "seller-token",
  });
  await setupSellerDashboardMocks(page, {
    seller: {
      id: "seller-1",
      store_name: "Pending Pottery",
      bio: "A new ceramics studio awaiting approval.",
      total_earnings_cents: 0,
      approval_status: "PENDING",
      orders: [],
      products: [],
    },
  });
  await setupMarketplaceMocks(page, { products: [] });

  await recorder.step(page, "Sign in as the unapproved seller", async () => {
    await page.addInitScript(() => {
      window.localStorage.setItem("token", "seller-token");
    });
    await page.goto("/seller/dashboard");
    await expect(page.getByRole("heading", { name: "Pending Pottery" })).toBeVisible();
  });

  await recorder.step(page, "Attempt to access product listing functionality", async () => {
    await expect(page.getByText("Seller account pending approval")).toBeVisible();
    await expect(page.getByText("Product publishing is disabled until an admin approves this seller account.")).toBeVisible();
  });

  await recorder.step(page, "Attempt to create or publish a product listing", async () => {
    await expect(page.getByRole("button", { name: "Create listing" })).toBeHidden();
    await expect(page.getByText("My listings (0)")).toBeVisible();
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:unapproved_seller_cannot_list_products");
  await recorder.save(testInfo);
});
