/**
 * mock-api.js
 * Playwright route-interception helpers used by UI spec files.
 * Each setup function intercepts a slice of the /api/* namespace and
 * fulfills requests with the data passed by the caller.
 */

/**
 * Intercept auth endpoints.
 *
 * @param {import('@playwright/test').Page} page
 * @param {{ me: object|null, token?: string }} opts
 *   me    - the user object returned by GET /api/auth/me (null → 401)
 *   token - the bearer token the test will place in localStorage
 */
export async function setupAuthMocks(page, { me, token } = {}) {
  await page.route(/\/api\/auth\/me/, async (route) => {
    if (!me) {
      await route.fulfill({ status: 401, contentType: "application/json", body: JSON.stringify({ error: "Unauthorized" }) });
      return;
    }
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(me) });
  });

  await page.route(/\/api\/auth\/login/, async (route) => {
    if (!me) {
      await route.fulfill({ status: 401, contentType: "application/json", body: JSON.stringify({ error: "Invalid credentials" }) });
      return;
    }
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ token: token ?? "mock-token", user: me }) });
  });

  await page.route(/\/api\/auth\/register/, async (route) => {
    const body = route.request().postData();
    const payload = body ? JSON.parse(body) : {};
    const user = {
      id: `user-${Date.now()}`,
      email: payload.email ?? "user@example.com",
      role: payload.role ?? "BUYER",
      status: "ACTIVE",
    };
    await route.fulfill({ status: 201, contentType: "application/json", body: JSON.stringify({ token: `mock-jwt-${user.id}`, user }) });
  });
}

/**
 * Intercept admin endpoints.
 *
 * @param {import('@playwright/test').Page} page
 * @param {{ sellers: object[], products: object[] }} opts
 */
export async function setupAdminMocks(page, { sellers = [], products = [] } = {}) {
  // Mutable copies so that PUT/DELETE mutations within a test session persist across reloads.
  const sellerList = sellers.map((s) => ({ ...s }));
  const productList = products.map((p) => ({ ...p }));

  await page.route(/\/api\/admin\/sellers\/[^/]+$/, async (route) => {
    const method = route.request().method();
    const url = route.request().url();
    const id = url.split("/api/admin/sellers/")[1]?.split("?")[0];

    if (method === "PUT" || method === "PATCH") {
      const body = route.request().postData();
      const payload = body ? JSON.parse(body) : {};
      const seller = sellerList.find((s) => s.id === id);
      if (!seller) {
        await route.fulfill({ status: 404, contentType: "application/json", body: JSON.stringify({ error: "Seller not found" }) });
        return;
      }
      if (payload.status) seller.status = payload.status;
      await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(seller) });
      return;
    }

    const seller = sellerList.find((s) => s.id === id);
    if (!seller) {
      await route.fulfill({ status: 404, contentType: "application/json", body: JSON.stringify({ error: "Seller not found" }) });
      return;
    }
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(seller) });
  });

  await page.route(/\/api\/admin\/sellers(\?.*)?$/, async (route) => {
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(sellerList) });
  });

  await page.route(/\/api\/admin\/products\/[^/]+$/, async (route) => {
    const method = route.request().method();
    const url = route.request().url();
    const id = url.split("/api/admin/products/")[1]?.split("?")[0];

    if (method === "DELETE") {
      const idx = productList.findIndex((p) => p.id === id);
      if (idx !== -1) productList.splice(idx, 1);
      await route.fulfill({ status: 204, contentType: "application/json", body: "" });
      return;
    }

    const product = productList.find((p) => p.id === id);
    if (!product) {
      await route.fulfill({ status: 404, contentType: "application/json", body: JSON.stringify({ error: "Product not found" }) });
      return;
    }
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(product) });
  });

  await page.route(/\/api\/admin\/products(\?.*)?$/, async (route) => {
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(productList) });
  });

  await page.route(/\/api\/admin\/payouts\/run/, async (route) => {
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ processed: 0, demoMode: true }) });
  });
}

/**
 * Intercept marketplace product listing endpoints.
 *
 * @param {import('@playwright/test').Page} page
 * @param {{ products: object[] }} opts
 */
export async function setupMarketplaceMocks(page, { products = [] } = {}) {
  await page.route(/\/api\/products(\?.*)?$/, async (route) => {
    const url = new URL(route.request().url());
    const category = url.searchParams.get("category");
    const keyword = url.searchParams.get("keyword");

    let result = [...products];
    if (category) result = result.filter((p) => p.category === category);
    if (keyword) {
      const kw = keyword.toLowerCase();
      result = result.filter(
        (p) =>
          p.title?.toLowerCase().includes(kw) ||
          (p.description ?? "").toLowerCase().includes(kw)
      );
    }

    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(result) });
  });

  await page.route(/\/api\/products\/[^/]+$/, async (route) => {
    const url = route.request().url();
    const id = url.split("/api/products/")[1]?.split("?")[0];
    const product = products.find((p) => p.id === id);
    if (!product) {
      await route.fulfill({ status: 404, contentType: "application/json", body: JSON.stringify({ error: "Product not found" }) });
      return;
    }
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(product) });
  });
}

/**
 * Intercept seller dashboard endpoints.
 *
 * @param {import('@playwright/test').Page} page
 * @param {{ seller: object }} opts
 *   seller - the dashboard object returned by GET /api/seller/dashboard
 */
export async function setupSellerDashboardMocks(page, { seller = {} } = {}) {
  await page.route(/\/api\/seller\/dashboard(\?.*)?$/, async (route) => {
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(seller) });
  });

  await page.route(/\/api\/seller\/products(\?.*)?$/, async (route) => {
    const prods = seller.products ?? [];
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(prods) });
  });

  await page.route(/\/api\/seller\/stats(\?.*)?$/, async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({
        total_earnings_cents: seller.total_earnings_cents ?? 0,
        total_orders: seller.orders?.length ?? 0,
        active_products: (seller.products ?? []).filter((p) => p.status === "ACTIVE").length,
      }),
    });
  });
}
