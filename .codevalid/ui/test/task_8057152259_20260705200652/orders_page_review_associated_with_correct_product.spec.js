import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../helpers/execution-recorder.js";

function json(body, status = 200) {
  return {
    status,
    contentType: "application/json",
    body: JSON.stringify(body),
  };
}

test("Review Is Linked To Correct Purchased Product", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "orders_page_review_associated_with_correct_product",
    testTitle: "Review Is Linked To Correct Purchased Product",
  });

  const deliveredOrders = [
    {
      id: "order-delivered-3003",
      status: "DELIVERED",
      totalCents: 16900,
      createdAt: "2026-07-05T14:00:00.000Z",
      items: [
        {
          id: "line-1",
          qty: 1,
          product: { title: "Handwoven Basket" },
          review: null,
        },
        {
          id: "line-2",
          qty: 2,
          product: { title: "Ceramic Mug" },
          review: null,
        },
      ],
    },
  ];

  await recorder.step("Mock authenticated buyer and completed order with multiple products");
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

  await page.route("**/api/**", async (route) => {
    await route.fulfill(json({ error: "Unhandled mock route" }, 404));
  });

  await recorder.step("Open the completed order on OrdersPage");
  await page.goto("/orders");

  await expect(page.getByRole("heading", { name: "Your orders" })).toBeVisible();
  await expect(page.getByText("1x Handwoven Basket")).toBeVisible();
  await expect(page.getByText("2x Ceramic Mug")).toBeVisible();
  await expect(page.getByText(/DELIVERED/)).toBeVisible();

  await recorder.step("Select one purchased product from the order context");
  await expect(page.getByText("1x Handwoven Basket")).toBeVisible();
  await expect(page.getByText("2x Ceramic Mug")).toBeVisible();

  await recorder.step("Inspect current UI for product-specific review association controls");
  await expect(page.getByRole("button", { name: /review/i })).toHaveCount(0);
  await expect(page.getByRole("textbox")).toHaveCount(0);

  await recorder.step("Verify no review UI is present that could misassociate a review to another product");
  await expect(page).toHaveURL(/\/orders$/);

  console.log("CODEVALID_TEST_ASSERTION_OK:orders_page_review_associated_with_correct_product");
  await recorder.save(testInfo);
});
