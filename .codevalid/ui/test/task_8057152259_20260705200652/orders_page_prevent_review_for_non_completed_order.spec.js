import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../helpers/execution-recorder.js";

function json(body, status = 200) {
  return {
    status,
    contentType: "application/json",
    body: JSON.stringify(body),
  };
}

test("Prevent Review Creation For Non-Completed Order", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "orders_page_prevent_review_for_non_completed_order",
    testTitle: "Prevent Review Creation For Non-Completed Order",
  });

  const nonCompletedOrders = [
    {
      id: "order-paid-2002",
      status: "PAID",
      totalCents: 9900,
      createdAt: "2026-07-05T13:00:00.000Z",
      items: [
        {
          id: "line-1",
          qty: 1,
          product: { title: "Ceramic Mug" },
          review: null,
        },
      ],
    },
  ];

  await recorder.step("Mock authenticated buyer and a non-completed order");
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
      await route.fulfill(json(nonCompletedOrders));
      return;
    }
    await route.fallback();
  });

  let deliverCalled = false;
  await page.route("**/api/orders/*/deliver", async (route) => {
    deliverCalled = true;
    await route.fulfill(json({ success: true }));
  });

  await page.route("**/api/**", async (route) => {
    await route.fulfill(json({ error: "Unhandled mock route" }, 404));
  });

  await recorder.step("Open a non-completed order on OrdersPage");
  await page.goto("/orders");

  await expect(page.getByRole("heading", { name: "Your orders" })).toBeVisible();
  await expect(page.getByText("1x Ceramic Mug")).toBeVisible();
  await expect(page.getByText(/PAID/)).toBeVisible();

  await recorder.step("Attempt to initiate a review creation flow for the product");
  await expect(page.getByRole("button", { name: /review/i })).toHaveCount(0);
  await expect(page.getByText("Confirm delivery (enables reviews)")).toHaveCount(0);

  await recorder.step("Verify the system does not expose review creation for non-completed purchases");
  expect(deliverCalled).toBe(false);
  await expect(page).toHaveURL(/\/orders$/);

  console.log("CODEVALID_TEST_ASSERTION_OK:orders_page_prevent_review_for_non_completed_order");
  await recorder.save(testInfo);
});
