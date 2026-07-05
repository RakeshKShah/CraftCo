import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../helpers/execution-recorder.js";

const sellerUser = {
  id: "seller-1",
  name: "Avery Seller",
  email: "seller@example.com",
  role: "SELLER",
  status: "ACTIVE",
};

const paidDashboard = {
  store_name: "Maker Studio",
  bio: "Handmade goods for thoughtful buyers.",
  status: "ACTIVE",
  total_earnings_cents: 4250,
  products: [
    {
      id: "product-1",
      title: "Handwoven Basket",
      priceCents: 8500,
      stockQty: 4,
      status: "ACTIVE",
    },
  ],
  orders: [
    {
      id: "line-1",
      order_id: "order-1001",
      product_title: "Handwoven Basket",
      qty: 1,
      buyer_email: "buyer@example.com",
      order_status: "PAID",
      seller_payout_cents: 7650,
    },
  ],
};

const shippedDashboard = {
  ...paidDashboard,
  orders: [
    {
      ...paidDashboard.orders[0],
      order_status: "SHIPPED",
    },
  ],
};

function json(body, status = 200) {
  return {
    status,
    contentType: "application/json",
    body: JSON.stringify(body),
  };
}

test("Seller updates an order to shipped status", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder(
    "seller_can_mark_order_as_shipped",
    "Seller updates an order to shipped status",
  );

  let currentDashboard = structuredClone(paidDashboard);
  let shipRequestCount = 0;

  await recorder.step("Mock authenticated seller session", async () => {
    await page.route("**/api/auth/me", async (route) => {
      await route.fulfill(json(sellerUser));
    });
  });

  await recorder.step("Mock seller dashboard before and after shipping", async () => {
    await page.route("**/api/seller/dashboard", async (route) => {
      await route.fulfill(json(currentDashboard));
    });
  });

  await recorder.step("Mock shipped-status update endpoint", async () => {
    await page.route("**/api/orders/order-1001/ship", async (route) => {
      if (route.request().method() !== "POST") {
        await route.fallback();
        return;
      }
      shipRequestCount += 1;
      currentDashboard = structuredClone(shippedDashboard);
      await route.fulfill(json({ success: true, order_id: "order-1001", status: "SHIPPED" }));
    });
  });

  await recorder.step("Block unexpected live api requests", async () => {
    await page.route("**/api/**", async (route) => {
      await route.fulfill(json({ error: "Unhandled mocked API request", url: route.request().url() }, 500));
    });
  });

  await recorder.step("Open the SellerDashboardPage", async () => {
    await page.goto("/seller/dashboard");
  });

  await recorder.step("Locate the purchased order", async () => {
    await expect(page.getByRole("heading", { name: "Orders to fulfill" })).toBeVisible();
    await expect(page.getByText("Handwoven Basket")).toBeVisible();
    await expect(page.getByText("buyer@example.com")).toBeVisible();
    await expect(page.getByText("PAID")).toBeVisible();
  });

  await recorder.step("Update the order using the available shipped-status functionality", async () => {
    await page.getByRole("button", { name: "Mark shipped" }).click();
  });

  await recorder.step("Save or confirm the order update if confirmation is required", async () => {
    await expect.poll(() => shipRequestCount).toBe(1);
    await expect(page.getByText("SHIPPED")).toBeVisible();
    await expect(page.getByRole("button", { name: "Mark shipped" })).toHaveCount(0);
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:seller_can_mark_order_as_shipped");
  await recorder.save(testInfo);
});
