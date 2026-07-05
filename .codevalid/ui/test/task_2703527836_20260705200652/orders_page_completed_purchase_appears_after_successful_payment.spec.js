import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../../../ui_test/helpers/execution-recorder.js";
import { setupAuthMocks } from "../../../../ui_test/helpers/mock-api.js";

test("Completed Stripe purchase appears in order management", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder(
    "orders_page_completed_purchase_appears_after_successful_payment",
    "Completed Stripe purchase appears in order management",
  );

  await setupAuthMocks(page, {
    me: {
      id: "buyer-1",
      email: "buyer@example.com",
      role: "BUYER",
      status: "ACTIVE",
    },
  });

  await page.addInitScript(() => {
    window.localStorage.setItem(
      "maker_market_cart",
      JSON.stringify([
        {
          product_id: "product-1",
          title: "Handwoven Basket",
          price_cents: 10000,
          qty: 1,
          photo: "https://example.com/basket.jpg",
        },
      ]),
    );
  });

  await page.route("**/api/orders/checkout", async (route) => {
    const payload = route.request().postDataJSON();
    expect(payload).toEqual({
      items: [
        {
          product_id: "product-1",
          qty: 1,
        },
      ],
    });

    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({
        order_id: "order-stripe-1",
        payment_status: "paid",
        payment_provider: "stripe",
        gross_total_cents: 10000,
      }),
    });
  });

  await page.route("**/api/orders", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify([
        {
          id: "order-stripe-1",
          status: "PAID",
          totalCents: 10000,
          createdAt: "2026-07-05T12:00:00.000Z",
          items: [
            {
              id: "line-stripe-1",
              qty: 1,
              product: {
                title: "Handwoven Basket",
              },
              review: null,
            },
          ],
        },
      ]),
    });
  });

  await recorder.step(page, "Open the cart page for checkout", async () => {
    await page.goto("/cart");
    await expect(page.getByRole("heading", { name: "Your cart" })).toBeVisible();
    await expect(page.getByText("Handwoven Basket")).toBeVisible();
    await expect(page.getByText("$100.00")).toBeVisible();
  });

  await recorder.step(page, "Complete Stripe-backed purchase from the cart", async () => {
    await page.getByRole("button", { name: "Place Order" }).click();
    await expect(page).toHaveURL(/\/orders\?success=order-stripe-1/);
  });

  await recorder.step(page, "Locate the newly completed purchase in order management", async () => {
    await expect(page.getByRole("heading", { name: "Your orders" })).toBeVisible();
    await expect(page.getByText("Order placed successfully!")).toBeVisible();
    await expect(page.getByText("Handwoven Basket")).toBeVisible();
  });

  await recorder.step(page, "Review order status and payout eligibility information", async () => {
    await expect(page.getByText("PAID")).toBeVisible();
    await expect(page.getByText("$100.00")).toBeVisible();
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:orders_page_completed_purchase_appears_after_successful_payment");
  await recorder.save(testInfo);
});
