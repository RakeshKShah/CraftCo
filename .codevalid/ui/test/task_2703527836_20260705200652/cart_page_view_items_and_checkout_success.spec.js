import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../helpers/execution-recorder.js";
import { setupMarketplaceMocks } from "../helpers/mock-api.js";

const buyerUser = {
  id: "buyer-1",
  email: "buyer@example.com",
  role: "BUYER",
  status: "ACTIVE",
};

const cartItems = [
  {
    product_id: "product-1",
    title: "Handwoven Basket",
    price_cents: 8500,
    qty: 1,
    photo: "https://example.com/basket.jpg",
  },
];

const completedOrder = {
  id: "order-1001",
  status: "PAID",
  totalCents: 8500,
  createdAt: "2026-07-05T12:00:00.000Z",
  items: [
    { id: "line-1", qty: 1, product: { title: "Handwoven Basket" }, review: null },
  ],
};

test("Buyer completes checkout successfully from CartPage", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder(testInfo, "cart_page_view_items_and_checkout_success");

  await recorder.step("Mock buyer session, cart checkout API, and orders API for a successful checkout");
  await setupMarketplaceMocks(page, { products: [] });

  await page.route("**/api/auth/me", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify(buyerUser),
    });
  });

  await page.route("**/api/orders/checkout", async (route) => {
    await expect(route.request().method()).toBe("POST");
    const payload = route.request().postDataJSON();
    expect(payload).toEqual({
      items: [{ product_id: "product-1", qty: 1 }],
    });
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({
        order_id: completedOrder.id,
        payment_status: "paid",
        payment_provider: "stripe",
      }),
    });
  });

  await page.route("**/api/orders", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify([completedOrder]),
    });
  });

  await recorder.step("Seed a cart with one product before opening the cart page");
  await page.addInitScript((items) => {
    window.localStorage.setItem("cart-items", JSON.stringify(items));
  }, cartItems);

  await recorder.step("Open the cart page");
  await page.goto("/cart");

  await recorder.step("Verify the cart item and total are displayed");
  await expect(page.getByRole("heading", { name: "Your cart" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Handwoven Basket" })).toBeVisible();
  await expect(page.getByText("$85.00")).toBeVisible();
  await expect(page.getByText("Total")).toBeVisible();

  await recorder.step("Proceed to checkout using the Place Order button");
  await page.getByRole("button", { name: "Place Order" }).click();

  await recorder.step("Wait for checkout completion and order confirmation view");
  await expect(page).toHaveURL(/\/orders\?success=order-1001$/);
  await expect(page.getByRole("heading", { name: "Your orders" })).toBeVisible();
  await expect(page.getByText("Order placed successfully!")).toBeVisible();
  await expect(page.getByText("Order #rder-1001")).toBeVisible();
  await expect(page.getByText("1x Handwoven Basket")).toBeVisible();
  await expect(page.getByText("$85.00")).toBeVisible();

  console.log("CODEVALID_TEST_ASSERTION_OK:cart_page_view_items_and_checkout_success");
  await recorder.save(testInfo);
});
