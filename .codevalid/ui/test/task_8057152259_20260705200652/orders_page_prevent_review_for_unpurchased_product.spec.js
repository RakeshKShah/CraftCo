import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../helpers/execution-recorder.js";

function json(body, status = 200) {
  return {
    status,
    contentType: "application/json",
    body: JSON.stringify(body),
  };
}

test("Prevent Review Creation For Product Without Completed Purchase", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "orders_page_prevent_review_for_unpurchased_product",
    testTitle: "Prevent Review Creation For Product Without Completed Purchase",
  });

  const buyerOrders = [
    {
      id: "order-paid-4004",
      status: "PAID",
      totalCents: 8500,
      createdAt: "2026-07-05T15:00:00.000Z",
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

  await recorder.step("Mock authenticated buyer with no completed purchase for the target product");
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
      await route.fulfill(json(buyerOrders));
      return;
    }
    await route.fallback();
  });

  await page.route("**/api/products/product-unpurchased", async (route) => {
    await route.fulfill(
      json({
        id: "product-unpurchased",
        title: "Wool Scarf",
        category: "Fashion",
        store_name: "Maker Studio",
        price_cents: 4200,
        stock_qty: 7,
        status: "ACTIVE",
        description: "Soft handmade scarf",
        photos: [],
        reviews: [],
      }),
    );
  });

  await page.route("**/api/**", async (route) => {
    await route.fulfill(json({ error: "Unhandled mock route" }, 404));
  });

  await recorder.step("Open OrdersPage and confirm the target product is not part of a completed purchase");
  await page.goto("/orders");
  await expect(page.getByRole("heading", { name: "Your orders" })).toBeVisible();
  await expect(page.getByText("1x Handwoven Basket")).toBeVisible();
  await expect(page.getByText("Wool Scarf")).toHaveCount(0);

  await recorder.step("Open the unpurchased product page");
  await page.goto("/product/product-unpurchased");
  await expect(page.getByRole("heading", { name: "Wool Scarf" })).toBeVisible();
  await expect(page.getByText("by Maker Studio")).toBeVisible();

  await recorder.step("Verify review creation is blocked because no completed purchase-linked UI exists");
  await expect(page.getByRole("button", { name: /review/i })).toHaveCount(0);
  await expect(page.getByRole("textbox")).toHaveCount(0);
  await expect(page.getByRole("heading", { name: "Reviews" })).toHaveCount(0);

  console.log("CODEVALID_TEST_ASSERTION_OK:orders_page_prevent_review_for_unpurchased_product");
  await recorder.save(testInfo);
});
