import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../helpers/execution-recorder.js";
import { setupAuthMocks, setupAdminMocks, setupMarketplaceMocks } from "../helpers/mock-api.js";

test("Admin can view all seller accounts", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder("admin_view_all_seller_accounts", "Admin can view all seller accounts");

  const sellers = [
    {
      id: "seller-1",
      email: "clay@example.com",
      store_name: "Clay Corner",
      status: "PENDING",
      product_count: 0,
    },
    {
      id: "seller-2",
      email: "loom@example.com",
      store_name: "Loom & Light",
      status: "ACTIVE",
      product_count: 3,
    },
  ];

  const products = [
    {
      id: "prod-1",
      title: "Ocean Mug",
      category: "ceramics",
      price_cents: 3200,
      stock_qty: 5,
      status: "ACTIVE",
      visible: true,
      store_name: "Clay Corner",
      seller_status: "PENDING",
    },
    {
      id: "prod-2",
      title: "Sunset Scarf",
      category: "textiles",
      price_cents: 4500,
      stock_qty: 8,
      status: "ACTIVE",
      visible: true,
      store_name: "Loom & Light",
      seller_status: "ACTIVE",
    },
  ];

  await setupAuthMocks(page, {
    me: {
      id: "admin-1",
      email: "admin@example.com",
      role: "ADMIN",
      status: "ACTIVE",
    },
    token: "admin-token",
  });
  await setupAdminMocks(page, { sellers, products });
  await setupMarketplaceMocks(page, { products: [] });

  await recorder.step(page, "Open the AdminPage", async () => {
    await page.addInitScript(() => {
      window.localStorage.setItem("token", "admin-token");
    });
    await page.goto("/admin");
    await expect(page.getByRole("heading", { name: "Admin panel" })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Sellers" })).toBeVisible();
  });

  await recorder.step(page, "Observe the list of seller accounts", async () => {
    await expect(page.getByText("Clay Corner")).toBeVisible();
    await expect(page.getByText("Loom & Light")).toBeVisible();
    await expect(page.getByText("clay@example.com")).toBeVisible();
    await expect(page.getByText("loom@example.com")).toBeVisible();
  });

  await recorder.step(page, "Verify that all existing seller accounts are displayed", async () => {
    await expect(page.getByRole("cell", { name: "Clay Corner" })).toBeVisible();
    await expect(page.getByRole("cell", { name: "Loom & Light" })).toBeVisible();
    await expect(page.getByText("PENDING")).toBeVisible();
    await expect(page.getByText("ACTIVE")).toBeVisible();
  });

  await recorder.step(page, "Verify seller profile information shown by current admin UI", async () => {
    await expect(page.getByRole("cell", { name: "Clay Corner" })).toBeVisible();
    await expect(page.getByRole("cell", { name: "Loom & Light" })).toBeVisible();
    await expect(page.getByRole("cell", { name: "clay@example.com" })).toBeVisible();
    await expect(page.getByRole("cell", { name: "loom@example.com" })).toBeVisible();
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:admin_view_all_seller_accounts");
  await recorder.save(testInfo);
});
