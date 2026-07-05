import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../helpers/execution-recorder.js";
import { setupMarketplaceMocks } from "../helpers/mock-api.js";

const buyerUser = {
  id: "buyer-1",
  email: "buyer@example.com",
  role: "BUYER",
  status: "ACTIVE",
};

const adminUser = {
  id: "admin-1",
  email: "admin@example.com",
  role: "ADMIN",
  status: "ACTIVE",
};

const sellerUser = {
  id: "seller-1",
  email: "seller@example.com",
  role: "SELLER",
  status: "ACTIVE",
};

const cartItems = [
  {
    product_id: "product-1",
    title: "Handwoven Basket",
    price_cents: 10000,
    qty: 1,
    photo: "https://example.com/basket.jpg",
  },
];

const payoutAdjustedDashboard = {
  store_name: "Maker Studio",
  bio: "Handmade goods for thoughtful buyers.",
  status: "ACTIVE",
  total_earnings_cents: 9000,
  products: [
    {
      id: "product-1",
      title: "Handwoven Basket",
      priceCents: 10000,
      stockQty: 3,
      status: "ACTIVE",
    },
  ],
  orders: [
    {
      id: "line-weekly-1",
      order_id: "order-weekly-1",
      product_title: "Handwoven Basket",
      qty: 1,
      buyer_email: "buyer@example.com",
      order_status: "PAID",
      seller_payout_cents: 9000,
    },
  ],
};

test("Completed sales are included in weekly seller payout processing", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder(testInfo, "cart_page_weekly_seller_payout_processing");

  await recorder.step("Mock buyer checkout, admin payout run, and seller dashboard payout records");
  await setupMarketplaceMocks(page, { products: [] });

  await page.route("**/api/auth/me", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify(buyerUser),
    });
  });

  await page.route("**/api/orders/checkout", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({
        order_id: "order-weekly-1",
        payment_status: "paid",
        payment_provider: "stripe",
      }),
    });
  });

  await page.route("**/api/orders", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify([
        {
          id: "order-weekly-1",
          status: "PAID",
          totalCents: 10000,
          createdAt: "2026-07-05T12:00:00.000Z",
          items: [{ id: "line-1", qty: 1, product: { title: "Handwoven Basket" }, review: null }],
        },
      ]),
    });
  });

  await page.route("**/api/admin/sellers", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify([
        {
          id: "seller-1",
          email: "seller@example.com",
          store_name: "Maker Studio",
          status: "ACTIVE",
          product_count: 1,
        },
      ]),
    });
  });

  await page.route("**/api/admin/products", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify([
        {
          id: "product-1",
          title: "Handwoven Basket",
          category: "Home",
          price_cents: 10000,
          stock_qty: 3,
          status: "ACTIVE",
          visible: true,
          store_name: "Maker Studio",
          seller_status: "ACTIVE",
        },
      ]),
    });
  });

  await page.route("**/api/admin/payouts/run", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({
        processed: 1,
        demoMode: true,
        payouts: [
          {
            order_id: "order-weekly-1",
            gross_sale_cents: 10000,
            commission_cents: 1000,
            seller_payout_cents: 9000,
          },
        ],
      }),
    });
  });

  await page.route("**/api/seller/dashboard", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify(payoutAdjustedDashboard),
    });
  });

  await recorder.step("Complete a purchase through the cart flow");
  await page.addInitScript((items) => {
    window.localStorage.setItem("cart-items", JSON.stringify(items));
  }, cartItems);
  await page.goto("/cart");
  await page.getByRole("button", { name: "Place Order" }).click();
  await expect(page).toHaveURL(/\/orders\?success=order-weekly-1$/);
  await expect(page.getByText("Order placed successfully!")).toBeVisible();

  await recorder.step("Switch to admin and initiate weekly payout processing");
  await page.unroute("**/api/auth/me");
  await page.route("**/api/auth/me", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify(adminUser),
    });
  });

  page.on("dialog", async (dialog) => {
    expect(dialog.message()).toContain("Processed 1 payouts (demo)");
    await dialog.accept();
  });

  await page.goto("/admin");
  await expect(page.getByRole("heading", { name: "Admin panel" })).toBeVisible();
  await page.getByRole("button", { name: "Run weekly payouts" }).click();

  await recorder.step("Switch to seller dashboard and verify completed sale is included after 10 percent commission deduction");
  await page.unroute("**/api/auth/me");
  await page.route("**/api/auth/me", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify(sellerUser),
    });
  });

  await page.goto("/seller/dashboard");
  await expect(page.getByRole("heading", { name: "Maker Studio" })).toBeVisible();
  await expect(page.getByText("Total earnings: $90.00")).toBeVisible();
  await expect(page.getByText("Handwoven Basket")).toBeVisible();
  await expect(page.getByText("$90.00")).toBeVisible();
  await expect(page.getByText("PAID")).toBeVisible();

  console.log("CODEVALID_TEST_ASSERTION_OK:cart_page_weekly_seller_payout_processing");
  await recorder.save(testInfo);
});
