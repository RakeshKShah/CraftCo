import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../helpers/execution-recorder.js";
import { setupMarketplaceMocks } from "../helpers/mock-api.js";

const buyerUser = {
  id: "buyer-1",
  email: "buyer@example.com",
  role: "BUYER",
  status: "ACTIVE",
};

const sellerUser = {
  id: "seller-1",
  email: "seller@example.com",
  role: "SELLER",
  status: "ACTIVE",
};

const cartItems = [
  {
    product_id: "product-1",
    title: "Handwoven Basket",
    price_cents: 10000,
    qty: 1,
    photo: "https://example.com/basket.jpg",
  },
];

const dashboardAfterSale = {
  store_name: "Maker Studio",
  bio: "Handmade goods for thoughtful buyers.",
  status: "ACTIVE",
  total_earnings_cents: 9000,
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

test("Completed sale applies 10 percent marketplace commission before seller payout", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder(testInfo, "cart_page_completed_sale_applies_marketplace_commission");

  await recorder.step("Mock buyer auth, successful checkout, and seller dashboard payout data with 10 percent deduction");
  await setupMarketplaceMocks(page, { products: [] });

  await page.route("**/api/auth/me", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify(buyerUser),
    });
  });

  await page.route("**/api/orders/checkout", async (route) => {
    const payload = route.request().postDataJSON();
    expect(payload).toEqual({
      items: [{ product_id: "product-1", qty: 1 }],
    });
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({
        order_id: "order-commission-1",
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
          id: "order-commission-1",
          status: "PAID",
          totalCents: 10000,
          createdAt: "2026-07-05T12:00:00.000Z",
          items: [{ id: "line-1", qty: 1, product: { title: "Handwoven Basket" }, review: null }],
        },
      ]),
    });
  });

  await page.route("**/api/seller/dashboard", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify(dashboardAfterSale),
    });
  });

  await recorder.step("Complete a purchase from the cart page");
  await page.addInitScript((items) => {
    window.localStorage.setItem("cart-items", JSON.stringify(items));
  }, cartItems);
  await page.goto("/cart");
  await expect(page.getByRole("heading", { name: "Handwoven Basket" })).toBeVisible();
  await expect(page.getByText("$100.00")).toBeVisible();
  await page.getByRole("button", { name: "Place Order" }).click();
  await expect(page).toHaveURL(/\/orders\?success=order-commission-1$/);
  await expect(page.getByText("Order placed successfully!")).toBeVisible();

  await recorder.step("Switch auth context to seller and review payout calculation on the seller dashboard");
  await page.unroute("**/api/auth/me");
  await page.route("**/api/auth/me", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify(sellerUser),
    });
  });

  await page.goto("/seller/dashboard");

  await recorder.step("Verify seller payout shows 90 dollars from a 100 dollar completed sale");
  await expect(page.getByRole("heading", { name: "Maker Studio" })).toBeVisible();
  await expect(page.getByText("Total earnings: $90.00")).toBeVisible();
  await expect(page.getByText("Handwoven Basket")).toBeVisible();
  await expect(page.getByText("buyer@example.com")).toBeVisible();
  await expect(page.getByText("$90.00")).toBeVisible();
  await expect(page.getByText("PAID")).toBeVisible();

  console.log("CODEVALID_TEST_ASSERTION_OK:cart_page_completed_sale_applies_marketplace_commission");
  await recorder.save(testInfo);
});
