import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../helpers/execution-recorder.js";

const sellerUser = {
  id: "seller-1",
  name: "Avery Seller",
  email: "seller@example.com",
  role: "SELLER",
  status: "ACTIVE",
};

const shippedDashboard = {
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
      order_status: "SHIPPED",
      seller_payout_cents: 7650,
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

test("Seller dashboard displays shipped status for fulfilled orders", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder(
    "seller_dashboard_shipped_status_visible_for_orders",
    "Seller dashboard displays shipped status for fulfilled orders",
  );

  await recorder.step("Mock authenticated seller session", async () => {
    await page.route("**/api/auth/me", async (route) => {
      await route.fulfill(json(sellerUser));
    });
  });

  await recorder.step("Mock seller dashboard containing an order already marked as shipped", async () => {
    await page.route("**/api/seller/dashboard", async (route) => {
      await route.fulfill(json(shippedDashboard));
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

  await recorder.step("Locate an order previously updated to shipped", async () => {
    await expect(page.getByRole("heading", { name: "Orders to fulfill" })).toBeVisible();
    await expect(page.getByText("Handwoven Basket")).toBeVisible();
    await expect(page.getByText("buyer@example.com")).toBeVisible();
  });

  await recorder.step("Observe the order status information", async () => {
    await expect(page.getByText("SHIPPED")).toBeVisible();
    await expect(page.getByRole("button", { name: "Mark shipped" })).toHaveCount(0);
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:seller_dashboard_shipped_status_visible_for_orders");
  await recorder.save(testInfo);
});
