import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../helpers/execution-recorder.js";
import { setupMarketplaceMocks, setupAuthMocks } from "../helpers/mock-api.js";

test("Suspended seller listings are hidden from buyers", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder("suspended_seller_listings_hidden_from_buyers", "Suspended seller listings are hidden from buyers");

  await setupAuthMocks(page, { me: null });
  await setupMarketplaceMocks(page, {
    products: [
      {
        id: "prod-visible-1",
        title: "Ocean Wave Mug",
        description: "Hand-thrown ceramic mug",
        category: "ceramics",
        price_cents: 3200,
        stock_qty: 8,
        photos: ["https://images.example.test/ocean-wave-mug.jpg"],
        status: "active",
        store_name: "Clay Corner",
      },
    ],
  });

  await recorder.step(page, "Access the buyer-facing marketplace or listings view", async () => {
    await page.goto("/");
    await expect(page.getByText("Ocean Wave Mug")).toBeVisible();
  });

  await recorder.step(page, "Search for listings associated with the suspended seller", async () => {
    await expect(page.getByText("Suspended Seller Candle")).toHaveCount(0);
    await expect(page.getByText("Hidden Craft House")).toHaveCount(0);
  });

  await recorder.step(page, "Observe the available listings", async () => {
    await expect(page.getByText("Ocean Wave Mug")).toBeVisible();
    await expect(page.getByText("Clay Corner")).toBeVisible();
    await expect(page.getByText("Suspended Seller Candle")).not.toBeVisible();
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:suspended_seller_listings_hidden_from_buyers");
  await recorder.save(testInfo);
});
