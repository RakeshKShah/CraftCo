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
  {
    product_id: "product-2",
    title: "Ceramic Mug",
    price_cents: 4200,
    qty: 2,
    photo: "https://example.com/mug.jpg",
  },
];

const completedOrder = {
  id: "order-2002",
  status: "PAID",
  totalCents: 16900,
  createdAt: "2026-07-05T12:30:00.000Z",
  items: [
    { id: "line-1", qty: 1, product: { title: "Handwoven Basket" }, review: null },
    { id: "line-2", qty: 2, product: { title: "Ceramic Mug" }, review: null },
  ],
};

test("Buyer completes checkout with multiple products in cart", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder(testInfo, "cart_page_checkout_with_multiple_products");

  await recorder.step("Mock authenticated buyer state and successful multi-product checkout APIs");
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
      items: [
        { product_id: "product-1", qty: 1 },
        { product_id: "product-2", qty: 2 },
      ],
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

  await recorder.step("Seed multiple products into cart storage");
  await page.addInitScript((items) => {
    window.localStorage.setItem("cart-items", JSON.stringify(items));
  }, cartItems);

  await recorder.step("Open the cart page and verify both products are visible");
  await page.goto("/cart");
  await expect(page.getByRole("heading", { name: "Your cart" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Handwoven Basket" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Ceramic Mug" })).toBeVisible();
  await expect(page.getByText("$85.00")).toBeVisible();
  await expect(page.getByText("$84.00")).toBeVisible();
  await expect(page.getByText("$169.00")).toBeVisible();

  await recorder.step("Proceed to checkout for all products in a single order");
  await page.getByRole("button", { name: "Place Order" }).click();

  await recorder.step("Verify the completed purchase contains all cart items");
  await expect(page).toHaveURL(/\/orders\?success=order-2002$/);
  await expect(page.getByText("Order placed successfully!")).toBeVisible();
  await expect(page.getByText("1x Handwoven Basket")).toBeVisible();
  await expect(page.getByText("2x Ceramic Mug")).toBeVisible();
  await expect(page.getByText("$169.00")).toBeVisible();

  console.log("CODEVALID_TEST_ASSERTION_OK:cart_page_checkout_with_multiple_products");
  await recorder.save(testInfo);
});
