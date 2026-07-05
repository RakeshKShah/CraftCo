import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../helpers/execution-recorder.js";
import { setupMarketplaceMocks } from "../helpers/mock-api.js";

const buyerUser = {
  id: "buyer-1",
  email: "buyer@example.com",
  role: "BUYER",
  status: "ACTIVE",
};

test("Checkout cannot proceed with an empty shopping cart", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder(testInfo, "cart_page_empty_cart_checkout_prevention");

  await recorder.step("Mock authenticated buyer state and block any unexpected checkout call");
  await setupMarketplaceMocks(page, { products: [] });

  await page.route("**/api/auth/me", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify(buyerUser),
    });
  });

  let checkoutCalled = false;
  await page.route("**/api/orders/checkout", async (route) => {
    checkoutCalled = true;
    await route.fulfill({
      status: 400,
      contentType: "application/json",
      body: JSON.stringify({ error: "Cart is empty" }),
    });
  });

  await recorder.step("Open the cart page with no cart items seeded");
  await page.addInitScript(() => {
    window.localStorage.setItem("cart-items", JSON.stringify([]));
  });
  await page.goto("/cart");

  await recorder.step("Verify the empty cart state is displayed");
  await expect(page.getByRole("heading", { name: "Your cart" })).toBeVisible();
  await expect(page.getByText("Your cart is empty.")).toBeVisible();
  await expect(page.getByRole("link", { name: "Continue browsing" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Place Order" })).toHaveCount(0);

  await recorder.step("Assert checkout does not proceed from the empty cart state");
  expect(checkoutCalled).toBe(false);
  await expect(page).toHaveURL(/\/cart$/);

  console.log("CODEVALID_TEST_ASSERTION_OK:cart_page_empty_cart_checkout_prevention");
  await recorder.save(testInfo);
});
