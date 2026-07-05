import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../helpers/execution-recorder.js";
import { setupMarketplaceMocks } from "../helpers/mock-api.js";

test("Category filtering shows available and sold-out products", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder("product_card_category_search_includes_all_stock_states", "Category filtering shows available and sold-out products");

  const mixedCategoryProducts = [
    {
      id: "prod-cat-available",
      title: "River Vase",
      description: "Tall ceramic vase",
      category: "ceramics",
      price_cents: 5200,
      stock_qty: 3,
      photos: ["https://images.example.test/river-vase.jpg"],
      status: "active",
      store_name: "Studio Earth"
    },
    {
      id: "prod-cat-soldout",
      title: "Moon Bowl",
      description: "Small serving bowl",
      category: "ceramics",
      price_cents: 2400,
      stock_qty: 0,
      photos: ["https://images.example.test/moon-bowl.jpg"],
      status: "sold_out",
      store_name: "Studio Earth"
    },
    {
      id: "prod-other-category",
      title: "Silver Thread Bracelet",
      description: "Fine jewelry bracelet",
      category: "jewelry",
      price_cents: 6100,
      stock_qty: 4,
      photos: ["https://images.example.test/silver-thread-bracelet.jpg"],
      status: "active",
      store_name: "Gem Grove"
    }
  ];

  await setupMarketplaceMocks(page, {
    products: mixedCategoryProducts,
    productDetails: Object.fromEntries(mixedCategoryProducts.map((product) => [product.id, product]))
  });

  try {
    await recorder.step(page, "Open the marketplace catalog page", async () => {
      await page.goto("/");
      await expect(page.getByRole("heading", { name: "Handmade goods from local artisans" })).toBeVisible();
    });

    await recorder.step(page, "Select a product category filter", async () => {
      await page.getByRole("button", { name: "ceramics" }).click();
    });

    await recorder.step(page, "View the filtered catalog results", async () => {
      await expect(page.getByRole("heading", { name: "River Vase" })).toBeVisible();
      await expect(page.getByRole("heading", { name: "Moon Bowl" })).toBeVisible();
    });

    await recorder.step(page, "Verify ProductCards for in-stock products are displayed", async () => {
      const availableLink = page.locator('a[href="/product/prod-cat-available"]');
      await expect(availableLink).toBeVisible();
      await expect(availableLink).not.toHaveClass(/grayscale/);
    });

    await recorder.step(page, "Verify ProductCards for sold-out products are displayed", async () => {
      const soldOutLink = page.locator('a[href="/product/prod-cat-soldout"]');
      await expect(soldOutLink).toBeVisible();
      await expect(soldOutLink.getByText("Sold out")).toBeVisible();
    });

    await recorder.step(page, "Verify sold-out products remain greyed out and labeled sold out", async () => {
      const soldOutLink = page.locator('a[href="/product/prod-cat-soldout"]');
      await expect(soldOutLink).toHaveClass(/grayscale/);
      await expect(soldOutLink).toHaveClass(/opacity-60/);
      await expect(page.getByRole("heading", { name: "Silver Thread Bracelet" })).toHaveCount(0);
    });

    console.log("CODEVALID_TEST_ASSERTION_OK:product_card_category_search_includes_all_stock_states");
  } finally {
    await recorder.save(testInfo);
  }
});
