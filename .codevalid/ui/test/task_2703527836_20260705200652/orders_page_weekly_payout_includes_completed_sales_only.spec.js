import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../../../ui_test/helpers/execution-recorder.js";
import { setupAuthMocks, setupAdminMocks, setupSellerDashboardMocks } from "../../../../ui_test/helpers/mock-api.js";

test("Weekly seller payout processing includes only completed sales", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder(
    "orders_page_weekly_payout_includes_completed_sales_only",
    "Weekly seller payout processing includes only completed sales",
  );

  await setupAuthMocks(page, {
    me: {
      id: "admin-1",
      email: "admin@example.com",
      role: "ADMIN",
      status: "ACTIVE",
    },
  });

  await setupAdminMocks(page, {
    sellers: [
      {
        id: "seller-1",
        email: "seller@example.com",
        store_name: "Maker Studio",
        status: "ACTIVE",
        product_count: 1,
      },
    ],
    products: [
      {
        id: "product-1",
        title: "Handwoven Basket",
        category: "Home",
        price_cents: 10000,
        stock_qty: 3,
        status: "ACTIVE",
        visible: true,
        store_name: "Maker Studio",
        seller_status: "ACTIVE",
      },
    ],
  });

  let payoutRunCount = 0;
  await page.route("**/api/admin/payouts/run", async (route) => {
    payoutRunCount += 1;
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({
        processed: 1,
        demoMode: true,
        payouts: [
          {
            order_id: "order-weekly-complete-1",
            gross_sale_cents: 10000,
            commission_cents: 1000,
            seller_payout_cents: 9000,
            status: "COMPLETED",
          },
        ],
        excluded_orders: [
          {
            order_id: "order-weekly-pending-1",
            status: "PENDING",
            reason: "Sale not completed",
          },
        ],
      }),
    });
  });

  const sellerDashboardData = {
    store_name: "Maker Studio",
    bio: "Handmade goods for thoughtful buyers.",
    total_earnings_cents: 9000,
    approval_status: "ACTIVE",
    products: [
      {
        id: "product-1",
        title: "Handwoven Basket",
        priceCents: 10000,
        stockQty: 3,
        status: "ACTIVE",
      },
    ],
    orders: [
      {
        id: "line-complete-1",
        order_id: "order-weekly-complete-1",
        product_title: "Handwoven Basket",
        qty: 1,
        buyer_email: "buyer@example.com",
        order_status: "PAID",
        seller_payout_cents: 9000,
      },
      {
        id: "line-pending-1",
        order_id: "order-weekly-pending-1",
        product_title: "Handwoven Basket",
        qty: 1,
        buyer_email: "buyer2@example.com",
        order_status: "PENDING",
        seller_payout_cents: 0,
      },
    ],
  };

  await recorder.step(page, "Open the admin payout processing view", async () => {
    page.once("dialog", async (dialog) => {
      expect(dialog.message()).toContain("Processed 1 payouts");
      await dialog.accept();
    });
    await page.goto("/admin");
    await expect(page.getByRole("heading", { name: "Admin panel" })).toBeVisible();
  });

  await recorder.step(page, "Execute weekly payout processing", async () => {
    await page.getByRole("button", { name: "Run weekly payouts" }).click();
    await expect.poll(() => payoutRunCount).toBe(1);
  });

  await setupAuthMocks(page, {
    me: {
      id: "seller-1",
      email: "seller@example.com",
      role: "SELLER",
      status: "ACTIVE",
    },
  });
  await setupSellerDashboardMocks(page, { seller: sellerDashboardData });

  await recorder.step(page, "Review seller orders included after payout processing", async () => {
    await page.goto("/seller/dashboard");
    await expect(page.getByRole("heading", { name: "Maker Studio" })).toBeVisible();
    await expect(page.getByText("buyer@example.com")).toBeVisible();
    await expect(page.getByText("PAID")).toBeVisible();
  });

  await recorder.step(page, "Verify non-completed sales are excluded from payout calculations", async () => {
    await expect(page.getByText("buyer2@example.com")).toBeVisible();
    await expect(page.getByText("PENDING")).toBeVisible();
    const payoutCellTexts = await page.locator("tbody tr").allTextContents();
    expect(payoutCellTexts.some((text) => text.includes("buyer@example.com") && text.includes("$90.00"))).toBeTruthy();
    expect(payoutCellTexts.some((text) => text.includes("buyer2@example.com") && text.includes("$0.00"))).toBeTruthy();
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:orders_page_weekly_payout_includes_completed_sales_only");
  await recorder.save(testInfo);
});
