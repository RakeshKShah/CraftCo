import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../helpers/execution-recorder.js";
import { setupAdminMocks, setupMarketplaceMocks } from "../helpers/mock-api.js";

test("Admin removes violating marketplace listing", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder("product_card_admin_can_remove_violating_listing", "Admin removes violating marketplace listing");

  const adminUser = {
    id: "admin-1",
    email: "admin@example.com",
    role: "ADMIN",
    status: "ACTIVE"
  };

  const sellers = [
    {
      id: "seller-1",
      email: "seller@example.com",
      store_name: "Rule Breakers",
      status: "ACTIVE",
      product_count: 1
    }
  ];

  let adminProducts = [
    {
      id: "prod-violating-1",
      title: "Banned Ivory Necklace",
      category: "jewelry",
      price_cents: 9900,
      stock_qty: 2,
      status: "ACTIVE",
      visible: true,
      store_name: "Rule Breakers",
      seller_status: "ACTIVE"
    }
  ];

  let marketplaceProducts = [
    {
      id: "prod-violating-1",
      title: "Banned Ivory Necklace",
      description: "Listing that violates marketplace rules",
      category: "jewelry",
      price_cents: 9900,
      stock_qty: 2,
      photos: ["https://images.example.test/banned-ivory-necklace.jpg"],
      status: "active",
      store_name: "Rule Breakers"
    }
  ];

  await page.addInitScript((user) => {
    localStorage.setItem("token", "admin-token");
    localStorage.setItem("user", JSON.stringify(user));
  }, adminUser);

  await page.route("**/api/auth/me", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify(adminUser)
    });
  });

  await setupAdminMocks(page, {
    sellers,
    dynamicProducts: () => adminProducts,
    onDeleteProduct: (id) => {
      adminProducts = adminProducts.map((product) =>
        product.id === id ? { ...product, status: "REMOVED", visible: false } : product
      );
      marketplaceProducts = marketplaceProducts.filter((product) => product.id !== id);
    }
  });

  await setupMarketplaceMocks(page, {
    dynamicProducts: () => marketplaceProducts,
    dynamicProductDetails: (id) => marketplaceProducts.find((product) => product.id === id)
  });

  try {
    await recorder.step(page, "Open the marketplace administration interface", async () => {
      page.once("dialog", (dialog) => dialog.accept());
      await page.goto("/admin");
      await expect(page.getByRole("heading", { name: "Admin panel" })).toBeVisible();
      await expect(page.getByRole("heading", { name: "All listings" })).toBeVisible();
    });

    await recorder.step(page, "Locate the violating product listing", async () => {
      await expect(page.getByText("Banned Ivory Necklace")).toBeVisible();
      await expect(page.getByText("Rule Breakers")).toBeVisible();
    });

    await recorder.step(page, "Remove the listing using the available moderation workflow", async () => {
      await page.getByRole("button", { name: "Remove" }).click();
      await expect(page.getByText("REMOVED")).toBeVisible();
    });

    await recorder.step(page, "Open the marketplace catalog page", async () => {
      await page.goto("/");
      await expect(page.getByRole("heading", { name: "Handmade goods from local artisans" })).toBeVisible();
    });

    await recorder.step(page, "Search for the removed product", async () => {
      await page.getByPlaceholder("Search handmade goods...").fill("Banned Ivory Necklace");
      await page.getByRole("button", { name: "Search" }).click();
      await expect(page.getByText("No products found.")).toBeVisible();
      await expect(page.getByRole("heading", { name: "Banned Ivory Necklace" })).toHaveCount(0);
    });

    console.log("CODEVALID_TEST_ASSERTION_OK:product_card_admin_can_remove_violating_listing");
  } finally {
    await recorder.save(testInfo);
  }
});
