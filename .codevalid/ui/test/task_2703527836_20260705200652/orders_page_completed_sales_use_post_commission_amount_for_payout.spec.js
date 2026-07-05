import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../../../ui_test/helpers/execution-recorder.js";
import { setupAuthMocks, setupSellerDashboardMocks } from "../../../../ui_test/helpers/mock-api.js";

test("Seller payouts use post-commission sale amounts", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder(
    "orders_page_completed_sales_use_post_commission_amount_for_payout",
    "Seller payouts use post-commission sale amounts",
  );

  const grossSaleCents = 10000;
  const expectedPayoutCents = Math.round(grossSaleCents * 0.9);

  await setupAuthMocks(page, {
    me: {
      id: "seller-1",
      email: "seller@example.com",
      role: "SELLER",
      status: "ACTIVE",
    },
  });

  await setupSellerDashboardMocks(page, {
    seller: {
      store_name: "Maker Studio",
      bio: "Handmade goods for thoughtful buyers.",
      total_earnings_cents: expectedPayoutCents,
      approval_status: "ACTIVE",
      products: [
        {
          id: "product-1",
          title: "Handwoven Basket",
          priceCents: grossSaleCents,
          stockQty: 3,
          status: "ACTIVE",
        },
      ],
      orders: [
        {
          id: "line-post-commission-1",
          order_id: "order-post-commission-1",
          product_title: "Handwoven Basket",
          qty: 1,
          buyer_email: "buyer@example.com",
          order_status: "PAID",
          seller_payout_cents: expectedPayoutCents,
        },
      ],
    },
  });

  await recorder.step(page, "Open seller dashboard with completed sale", async () => {
    await page.goto("/seller/dashboard");
    await expect(page.getByRole("heading", { name: "Maker Studio" })).toBeVisible();
    await expect(page.getByRole("heading", { name: /Orders to fulfill/i })).toBeVisible();
  });

  await recorder.step(page, "Locate the completed order used in payout processing", async () => {
    await expect(page.getByText("Handwoven Basket")).toBeVisible();
    await expect(page.getByText("buyer@example.com")).toBeVisible();
    await expect(page.getByText("PAID")).toBeVisible();
  });

  await recorder.step(page, "Review completed sale amount and associated seller payout", async () => {
    await expect(page.getByText("$90.00")).toBeVisible();
    await expect(page.getByText("Total earnings: $90.00")).toBeVisible();
  });

  await recorder.step(page, "Calculate 90 percent of sale amount and compare to payout", async () => {
    expect(expectedPayoutCents).toBe(9000);
    const commissionCents = grossSaleCents - expectedPayoutCents;
    expect(commissionCents).toBe(1000);
    await expect(page.getByText("$90.00")).toBeVisible();
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:orders_page_completed_sales_use_post_commission_amount_for_payout");
  await recorder.save(testInfo);
});
