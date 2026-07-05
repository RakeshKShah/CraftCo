import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../helpers/execution-recorder.js";

const sellerUser = {
  id: "seller-1",
  name: "Avery Seller",
  email: "seller@example.com",
  role: "SELLER",
  status: "ACTIVE",
};

const dashboardWithPurchasedOrder = {
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

function json(body, status = 200) {
  return {
    status,
    contentType: "application/json",
    body: JSON.stringify(body),
  };
}

test("Seller receives notification after buyer purchases a product", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder(
    "seller_dashboard_displays_order_fulfillment_notification",
    "Seller receives notification after buyer purchases a product",
  );

  await recorder.step("Mock authenticated seller session", async () => {
    await page.route("**/api/auth/me", async (route) => {
      await route.fulfill(json(sellerUser));
    });
  });

  await recorder.step("Mock seller dashboard with newly purchased order awaiting fulfillment", async () => {
    await page.route("**/api/seller/dashboard", async (route) => {
      await route.fulfill(json(dashboardWithPurchasedOrder));
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

  await recorder.step("Observe the seller dashboard for newly triggered order fulfillment notifications related to the buyer purchase", async () => {
    await expect(page.getByRole("heading", { name: "Maker Studio" })).toBeVisible();
    await expect(page.getByRole("heading", { name: "Orders to fulfill" })).toBeVisible();
    await expect(page.getByText("Handwoven Basket")).toBeVisible();
    await expect(page.getByText("buyer@example.com")).toBeVisible();
    await expect(page.getByRole("button", { name: "Mark shipped" })).toBeVisible();
    await expect(page.getByText("PAID")).toBeVisible();
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:seller_dashboard_displays_order_fulfillment_notification");
  await recorder.save(testInfo);
});
