import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../helpers/execution-recorder.js";
import { setupMarketplaceMocks } from "../helpers/mock-api.js";

test("Display sold-out product state", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder("product_card_displays_sold_out_state", "Display sold-out product state");

  const soldOutProduct = {
    id: "prod-soldout-1",
    title: "Sunset Scarf",
    description: "Soft woven scarf",
    category: "textiles",
    price_cents: 4500,
    stock_qty: 0,
    photos: ["https://images.example.test/sunset-scarf.jpg"],
    status: "sold_out",
    store_name: "Loom & Light"
  };

  await setupMarketplaceMocks(page, {
    products: [soldOutProduct],
    productDetails: {
      "prod-soldout-1": soldOutProduct
    }
  });

  try {
    await recorder.step(page, "Open the marketplace catalog page containing ProductCard components", async () => {
      await page.goto("/");
      await expect(page.getByRole("heading", { name: "Sunset Scarf" })).toBeVisible();
    });

    await recorder.step(page, "Locate a product with stock quantity equal to 0", async () => {
      await expect(page.getByText("by Loom & Light")).toBeVisible();
      await expect(page.getByText("$45.00")).toBeVisible();
    });

    await recorder.step(page, "Verify the ProductCard remains visible in the catalog", async () => {
      const productLink = page.getByRole("link", { name: /Sunset Scarf/i });
      await expect(productLink).toBeVisible();
    });

    await recorder.step(page, "Verify the ProductCard appears visually greyed out", async () => {
      const productLink = page.locator('a[href="/product/prod-soldout-1"]');
      await expect(productLink).toHaveClass(/opacity-60/);
      await expect(productLink).toHaveClass(/grayscale/);
    });

    await recorder.step(page, "Verify the ProductCard displays a sold out label", async () => {
      await expect(page.getByText("Sold out")).toBeVisible();
    });

    await recorder.step(page, "Verify the product photo and pricing remain visible", async () => {
      await expect(page.getByRole("img", { name: "Sunset Scarf" })).toBeVisible();
      await expect(page.getByText("$45.00")).toBeVisible();
    });

    console.log("CODEVALID_TEST_ASSERTION_OK:product_card_displays_sold_out_state");
  } finally {
    await recorder.save(testInfo);
  }
});
