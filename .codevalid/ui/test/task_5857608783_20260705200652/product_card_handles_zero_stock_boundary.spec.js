import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../helpers/execution-recorder.js";
import { setupMarketplaceMocks } from "../helpers/mock-api.js";

test("Zero-stock boundary condition renders sold-out state", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder("product_card_handles_zero_stock_boundary", "Zero-stock boundary condition renders sold-out state");

  const inStockVersion = {
    id: "prod-boundary-1",
    title: "Dawn Pendant",
    description: "Hammered metal pendant",
    category: "jewelry",
    price_cents: 7800,
    stock_qty: 1,
    photos: ["https://images.example.test/dawn-pendant.jpg"],
    status: "active",
    store_name: "North Forge"
  };

  const soldOutVersion = {
    ...inStockVersion,
    stock_qty: 0,
    status: "sold_out"
  };

  let currentProducts = [inStockVersion];
  let currentDetails = { "prod-boundary-1": inStockVersion };

  await setupMarketplaceMocks(page, {
    dynamicProducts: () => currentProducts,
    dynamicProductDetails: (id) => currentDetails[id]
  });

  try {
    await recorder.step(page, "Open the marketplace catalog page", async () => {
      await page.goto("/");
      await expect(page.getByRole("heading", { name: "Dawn Pendant" })).toBeVisible();
    });

    await recorder.step(page, "Locate a ProductCard for a product with stock quantity of 1", async () => {
      await page.getByRole("link", { name: /Dawn Pendant/i }).click();
      await expect(page.getByText("1 in stock")).toBeVisible();
    });

    await recorder.step(page, "Update the product stock quantity to 0 through the listing management workflow", async () => {
      currentProducts = [soldOutVersion];
      currentDetails = { "prod-boundary-1": soldOutVersion };
    });

    await recorder.step(page, "Refresh or revisit the catalog view", async () => {
      await page.goto("/");
      await page.reload();
    });

    await recorder.step(page, "Locate the updated ProductCard", async () => {
      await expect(page.getByRole("heading", { name: "Dawn Pendant" })).toBeVisible();
    });

    await recorder.step(page, "Verify the ProductCard remains visible", async () => {
      const productLink = page.locator('a[href="/product/prod-boundary-1"]');
      await expect(productLink).toBeVisible();
    });

    await recorder.step(page, "Verify the ProductCard is greyed out", async () => {
      const productLink = page.locator('a[href="/product/prod-boundary-1"]');
      await expect(productLink).toHaveClass(/grayscale/);
      await expect(productLink).toHaveClass(/opacity-60/);
    });

    await recorder.step(page, "Verify the ProductCard displays a sold out label", async () => {
      await expect(page.locator('a[href="/product/prod-boundary-1"]')).toContainText("Sold out");
    });

    console.log("CODEVALID_TEST_ASSERTION_OK:product_card_handles_zero_stock_boundary");
  } finally {
    await recorder.save(testInfo);
  }
});
