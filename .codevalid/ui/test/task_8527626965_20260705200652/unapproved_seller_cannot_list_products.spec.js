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
    // Navigate to "/" first so auth loads before hitting the protected seller dashboard.
    await page.goto("/");
    await expect(page.getByText("pending@example.com")).toBeVisible();
    await page.getByRole("link", { name: "Seller Dashboard" }).click();
    await expect(page.getByRole("heading", { name: "Awaiting approval" })).toBeVisible();
  });

  await recorder.step(page, "Attempt to access product listing functionality", async () => {
    await expect(page.getByText("Awaiting approval")).toBeVisible();
    await expect(page.getByText("An admin must approve you before you can list products.")).toBeVisible();
  });

  await recorder.step(page, "Attempt to create or publish a product listing", async () => {
    await expect(page.getByRole("button", { name: "Create listing" })).toHaveCount(0);
    await expect(page.getByRole("heading", { name: "Awaiting approval" })).toBeVisible();
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:unapproved_seller_cannot_list_products");
  await recorder.save(testInfo);
});
