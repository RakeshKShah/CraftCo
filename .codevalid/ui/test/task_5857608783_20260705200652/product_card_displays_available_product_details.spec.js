import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../helpers/execution-recorder.js";
import { setupMarketplaceMocks } from "../helpers/mock-api.js";

test("Display available product information", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder("product_card_displays_available_product_details", "Display available product information");

  const products = [
    {
      id: "prod-available-1",
      title: "Ocean Wave Mug",
      description: "Hand-thrown ceramic mug",
      category: "ceramics",
      price_cents: 3200,
      stock_qty: 8,
      photos: ["https://images.example.test/ocean-wave-mug.jpg"],
      status: "active",
      store_name: "Clay Corner"
    }
  ];

  await setupMarketplaceMocks(page, {
    products,
    productDetails: {
      "prod-available-1": products[0]
    }
  });

  try {
    await recorder.step(page, "Open the marketplace catalog page containing ProductCard components", async () => {
      await page.goto("/");
      await expect(page.getByRole("heading", { name: "Handmade goods from local artisans" })).toBeVisible();
    });

    await recorder.step(page, "Locate a product with stock quantity greater than 0", async () => {
      await expect(page.getByRole("heading", { name: "Ocean Wave Mug" })).toBeVisible();
      await expect(page.getByText("by Clay Corner")).toBeVisible();
    });

    await recorder.step(page, "Verify the ProductCard displays the product photo", async () => {
      await expect(page.getByRole("img", { name: "Ocean Wave Mug" })).toBeVisible();
    });

    await recorder.step(page, "Verify the ProductCard displays the product price", async () => {
      await expect(page.getByText("$32.00")).toBeVisible();
    });

    await recorder.step(page, "Verify the ProductCard displays the available product details", async () => {
      await expect(page.getByText("ceramics")).toBeVisible();
      await expect(page.getByRole("link", { name: /Ocean Wave Mug/i })).toBeVisible();
    });

    await recorder.step(page, "Verify the ProductCard does not display a sold out label", async () => {
      await expect(page.getByText("Sold out")).toHaveCount(0);
    });

    await recorder.step(page, "Verify the product is displayed as available", async () => {
      await page.getByRole("link", { name: /Ocean Wave Mug/i }).click();
      await expect(page).toHaveURL(/\/product\/prod-available-1$/);
      await expect(page.getByRole("button", { name: "Add to cart" })).toBeVisible();
      await expect(page.getByText("8 in stock")).toBeVisible();
    });

    console.log("CODEVALID_TEST_ASSERTION_OK:product_card_displays_available_product_details");
  } finally {
    await recorder.save(testInfo);
  }
});
