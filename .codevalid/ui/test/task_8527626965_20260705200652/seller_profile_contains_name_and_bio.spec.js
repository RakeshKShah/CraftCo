import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../helpers/execution-recorder.js";
import { setupAuthMocks, setupSellerDashboardMocks, setupMarketplaceMocks } from "../helpers/mock-api.js";

test("Seller profile contains store name and bio", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder("seller_profile_contains_name_and_bio", "Seller profile contains store name and bio");

  await setupAuthMocks(page, {
    me: {
      id: "seller-1",
      email: "seller@example.com",
      role: "SELLER",
      status: "ACTIVE",
    },
    token: "seller-token",
  });
  await setupSellerDashboardMocks(page, {
    seller: {
      id: "seller-1",
      store_name: "Willow Workshop",
      bio: "Handcrafted home goods with natural textures.",
      total_earnings_cents: 12500,
      approval_status: "ACTIVE",
      orders: [],
      products: [
        {
          id: "prod-1",
          title: "Willow Basket",
          priceCents: 4800,
          status: "ACTIVE",
        },
      ],
    },
  });
  await setupMarketplaceMocks(page, { products: [] });

  await recorder.step(page, "Open the seller dashboard profile view", async () => {
    await page.addInitScript(() => {
      window.localStorage.setItem("token", "seller-token");
    });
    await page.goto("/seller/dashboard");
  });

  await recorder.step(page, "Locate the seller account profile information", async () => {
    await expect(page.getByRole("heading", { name: "Willow Workshop" })).toBeVisible();
  });

  await recorder.step(page, "Review the seller profile information", async () => {
    await expect(page.getByText("Handcrafted home goods with natural textures.")).toBeVisible();
    await expect(page.getByText("Total earnings:")).toBeVisible();
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:seller_profile_contains_name_and_bio");
  await recorder.save(testInfo);
});
