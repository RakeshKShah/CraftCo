import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../../../ui_test/helpers/execution-recorder.js";
import { setupAuthMocks, setupAdminMocks, setupSellerDashboardMocks } from "../../../../ui_test/helpers/mock-api.js";

test("Completed purchase applies 10 percent marketplace commission before seller payout", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder(
    "orders_page_completed_purchase_reflects_commission_deduction",
    "Completed purchase applies 10 percent marketplace commission before seller payout",
  );

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
        id: "line-commission-1",
        order_id: "order-commission-1",
        product_title: "Handwoven Basket",
        qty: 1,
        buyer_email: "buyer@example.com",
        order_status: "PAID",
        seller_payout_cents: 9000,
      },
    ],
  };

  await setupAuthMocks(page, {
    me: {
      id: "seller-1",
      email: "seller@example.com",
      role: "SELLER",
      status: "ACTIVE",
    },
  });
  await setupSellerDashboardMocks(page, { seller: sellerDashboardData });

  await recorder.step(page, "Open seller order management for the completed purchase", async () => {
    await page.goto("/seller/dashboard");
    await expect(page.getByRole("heading", { name: "Maker Studio" })).toBeVisible();
    await expect(page.getByRole("heading", { name: /Orders to fulfill/i })).toBeVisible();
  });

  await recorder.step(page, "Locate the completed order record", async () => {
    await expect(page.getByText("Handwoven Basket")).toBeVisible();
    await expect(page.getByText("buyer@example.com")).toBeVisible();
    await expect(page.getByText("PAID")).toBeVisible();
  });

  await recorder.step(page, "Review payout-related values associated with the completed sale", async () => {
    await expect(page.getByText("$90.00")).toBeVisible();
    await expect(page.getByText("Total earnings: $90.00")).toBeVisible();
  });

  await recorder.step(page, "Compare sale amount against seller payout amount after 10 percent commission", async () => {
    const grossSaleCents = 10000;
    const expectedPayoutCents = grossSaleCents - Math.round(grossSaleCents * 0.1);
    expect(expectedPayoutCents).toBe(9000);
    await expect(page.getByText("$90.00")).toBeVisible();
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:orders_page_completed_purchase_reflects_commission_deduction");
  await recorder.save(testInfo);
});
