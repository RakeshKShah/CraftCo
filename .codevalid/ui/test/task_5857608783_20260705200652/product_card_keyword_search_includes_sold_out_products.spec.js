import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../helpers/execution-recorder.js";
import { setupMarketplaceMocks } from "../helpers/mock-api.js";

test("Keyword search returns available and sold-out products", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder("product_card_keyword_search_includes_sold_out_products", "Keyword search returns available and sold-out products");

  const availableProduct = {
    id: "prod-keyword-available",
    title: "Forest Mug",
    description: "Green glazed mug",
    category: "ceramics",
    price_cents: 2800,
    stock_qty: 5,
    photos: ["https://images.example.test/forest-mug.jpg"],
    status: "active",
    store_name: "Clay Corner"
  };

  const soldOutProduct = {
    id: "prod-keyword-soldout",
    title: "Forest Mug Large",
    description: "Large green glazed mug",
    category: "ceramics",
    price_cents: 3600,
    stock_qty: 0,
    photos: ["https://images.example.test/forest-mug-large.jpg"],
    status: "sold_out",
    store_name: "Clay Corner"
  };

  await setupMarketplaceMocks(page, {
    products: [availableProduct, soldOutProduct],
    productDetails: {
      "prod-keyword-available": availableProduct,
      "prod-keyword-soldout": soldOutProduct
    }
  });

  try {
    await recorder.step(page, "Open the marketplace catalog page", async () => {
      await page.goto("/");
      await expect(page.getByRole("heading", { name: "Handmade goods from local artisans" })).toBeVisible();
    });

    await recorder.step(page, "Enter a valid product keyword into the catalog search input", async () => {
      await page.getByPlaceholder("Search handmade goods...").fill("Forest Mug");
    });

    await recorder.step(page, "Execute the search", async () => {
      await page.getByRole("button", { name: "Search" }).click();
    });

    await recorder.step(page, "Verify ProductCards matching the keyword are displayed", async () => {
      await expect(page.getByRole("heading", { name: "Forest Mug" })).toBeVisible();
      await expect(page.getByRole("heading", { name: "Forest Mug Large" })).toBeVisible();
    });

    await recorder.step(page, "Verify available matching products are visible", async () => {
      const availableLink = page.locator('a[href="/product/prod-keyword-available"]');
      await expect(availableLink).toBeVisible();
      await expect(availableLink).not.toHaveClass(/grayscale/);
    });

    await recorder.step(page, "Verify sold-out matching products are also visible and still marked sold out", async () => {
      const soldOutLink = page.locator('a[href="/product/prod-keyword-soldout"]');
      await expect(soldOutLink).toBeVisible();
      await expect(soldOutLink).toHaveClass(/grayscale/);
      await expect(soldOutLink.getByText("Sold out")).toBeVisible();
    });

    console.log("CODEVALID_TEST_ASSERTION_OK:product_card_keyword_search_includes_sold_out_products");
  } finally {
    await recorder.save(testInfo);
  }
});
