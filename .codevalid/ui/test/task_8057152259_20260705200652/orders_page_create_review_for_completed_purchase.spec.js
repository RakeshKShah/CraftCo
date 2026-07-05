import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../helpers/execution-recorder.js";

function json(body, status = 200) {
  return {
    status,
    contentType: "application/json",
    body: JSON.stringify(body),
  };
}

test("Create Review For Product From Completed Order", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "orders_page_create_review_for_completed_purchase",
    testTitle: "Create Review For Product From Completed Order",
  });

  const deliveredOrders = [
    {
      id: "order-delivered-1001",
      status: "DELIVERED",
      totalCents: 8500,
      createdAt: "2026-07-05T12:00:00.000Z",
      items: [
        {
          id: "line-1",
          qty: 1,
          product: { title: "Handwoven Basket" },
          review: null,
        },
      ],
    },
  ];

  await recorder.step("Mock authenticated buyer and completed order data");
  await page.route("**/api/auth/me", async (route) => {
    await route.fulfill(
      json({
        id: "buyer-1",
        email: "buyer@example.com",
        role: "BUYER",
        status: "ACTIVE",
      }),
    );
  });

  await page.route("**/api/orders", async (route) => {
    if (route.request().method() === "GET") {
      await route.fulfill(json(deliveredOrders));
      return;
    }
    await route.fallback();
  });

  await page.route("**/api/orders/*/deliver", async (route) => {
    await route.fulfill(json({ success: true }));
  });

  await page.route("**/api/products/**", async (route) => {
    await route.fulfill(
      json({
        id: "product-1",
        title: "Handwoven Basket",
        category: "Home",
        store_name: "Maker Studio",
        price_cents: 8500,
        stock_qty: 3,
        status: "ACTIVE",
        description: "Handmade basket",
        photos: [],
        reviews: [],
      }),
    );
  });

  await page.route("**/api/**", async (route) => {
    await route.fulfill(json({ error: "Unhandled mock route" }, 404));
  });

  await recorder.step("Open OrdersPage");
  await page.goto("/orders");

  await expect(page.getByRole("heading", { name: "Your orders" })).toBeVisible();
  await expect(page.getByText("1x Handwoven Basket")).toBeVisible();
  await expect(page.getByText(/DELIVERED/)).toBeVisible();

  await recorder.step("Locate the purchased product within the completed order");
  const productLine = page.getByText("1x Handwoven Basket");
  await expect(productLine).toBeVisible();

  await recorder.step("Attempt to find a review creation flow for the purchased product");
  await expect(page.getByRole("button", { name: /review/i })).toHaveCount(0);
  await expect(page.getByRole("textbox")).toHaveCount(0);

  await recorder.step("Validate current UI does not expose review entry despite delivered state");
  await expect(page.getByText("Confirm delivery (enables reviews)")).toHaveCount(0);
  await expect(page).toHaveURL(/\/orders$/);

  console.log("CODEVALID_TEST_ASSERTION_OK:orders_page_create_review_for_completed_purchase");
  await recorder.save(testInfo);
});
