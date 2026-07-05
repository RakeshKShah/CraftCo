/**
 * mock-server.js
 * Lightweight HTTP mock server that intercepts API calls during Playwright tests.
 * Serves fake responses matching the backend API contract so tests run without
 * a live backend or database.
 *
 * Usage (standalone):
 *   node .codevalid/ui/mock/mock-server.js
 *
 * Usage (from Playwright):
 *   Import setupMockRoutes and call it inside a test or fixture with the `page` object.
 */

import http from "http";
import { URL } from "url";
import {
  MOCK_PRODUCTS,
  MOCK_USERS,
  MOCK_ORDERS,
  MOCK_AUTH_TOKENS,
  MOCK_SELLER_STATS,
} from "./mock-data.js";

const DEFAULT_PORT = 4000;

// ─── Route handlers ──────────────────────────────────────────────────────────

function handleProducts(req, res, url) {
  const category = url.searchParams.get("category");
  const keyword = url.searchParams.get("keyword");

  let products = [...MOCK_PRODUCTS];

  if (category) {
    products = products.filter((p) => p.category === category);
  }

  if (keyword) {
    const kw = keyword.toLowerCase();
    products = products.filter(
      (p) =>
        p.title.toLowerCase().includes(kw) ||
        (p.description ?? "").toLowerCase().includes(kw)
    );
  }

  return json(res, 200, products);
}

function handleProductById(req, res, id) {
  const product = MOCK_PRODUCTS.find((p) => p.id === id);
  if (!product) return json(res, 404, { error: "Product not found" });
  return json(res, 200, product);
}

function handleLogin(req, res, body) {
  const { email, password } = body ?? {};
  const token = MOCK_AUTH_TOKENS[email];

  if (!token || !password) {
    return json(res, 401, { error: "Invalid credentials" });
  }

  const userKey = Object.keys(MOCK_USERS).find(
    (k) => MOCK_USERS[k].email === email
  );
  const user = MOCK_USERS[userKey];

  return json(res, 200, { token, user });
}

function handleRegister(req, res, body) {
  const { email, password, role, storeName } = body ?? {};
  if (!email || !password) {
    return json(res, 400, { error: "email and password required" });
  }

  const newUser = {
    id: `user-${Date.now()}`,
    email,
    role: role ?? "BUYER",
    status: "ACTIVE",
    ...(role === "SELLER" && storeName
      ? {
          sellerProfile: {
            id: `sp-${Date.now()}`,
            storeName,
            bio: "",
          },
        }
      : {}),
  };

  const token = `mock-jwt-${newUser.id}`;
  return json(res, 201, { token, user: newUser });
}

function handleMe(req, res, authHeader) {
  const token = authHeader?.replace("Bearer ", "");
  const entry = Object.entries(MOCK_AUTH_TOKENS).find(
    ([, t]) => t === token
  );

  if (!entry) return json(res, 401, { error: "Unauthorized" });

  const userKey = Object.keys(MOCK_USERS).find(
    (k) => MOCK_USERS[k].email === entry[0]
  );
  return json(res, 200, MOCK_USERS[userKey]);
}

function handleOrders(req, res) {
  return json(res, 200, MOCK_ORDERS);
}

function handleCart(req, res, body) {
  if (req.method === "POST") {
    return json(res, 200, { message: "Item added to cart", cart: body });
  }
  return json(res, 200, { items: [] });
}

function handleSellerProducts(req, res) {
  return json(res, 200, MOCK_PRODUCTS);
}

function handleSellerStats(req, res) {
  return json(res, 200, MOCK_SELLER_STATS);
}

function handleAdminUsers(req, res) {
  return json(res, 200, Object.values(MOCK_USERS));
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function json(res, status, data) {
  const body = JSON.stringify(data);
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
  });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve) => {
    let data = "";
    req.on("data", (chunk) => (data += chunk));
    req.on("end", () => {
      try {
        resolve(data ? JSON.parse(data) : {});
      } catch {
        resolve({});
      }
    });
  });
}

// ─── Router ──────────────────────────────────────────────────────────────────

async function router(req, res) {
  // CORS pre-flight
  if (req.method === "OPTIONS") {
    res.writeHead(204, {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
      "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
    });
    return res.end();
  }

  const base = `http://localhost`;
  const url = new URL(req.url ?? "/", base);
  const pathname = url.pathname;
  const auth = req.headers["authorization"];
  const body = ["POST", "PUT", "PATCH"].includes(req.method ?? "")
    ? await readBody(req)
    : null;

  // Products
  if (pathname === "/products" && req.method === "GET") {
    return handleProducts(req, res, url);
  }
  const productMatch = pathname.match(/^\/products\/([^/]+)$/);
  if (productMatch && req.method === "GET") {
    return handleProductById(req, res, productMatch[1]);
  }

  // Auth
  if (pathname === "/auth/login" && req.method === "POST") {
    return handleLogin(req, res, body);
  }
  if (pathname === "/auth/register" && req.method === "POST") {
    return handleRegister(req, res, body);
  }
  if (pathname === "/auth/me" && req.method === "GET") {
    return handleMe(req, res, auth);
  }

  // Orders
  if (pathname === "/orders" && req.method === "GET") {
    return handleOrders(req, res);
  }

  // Cart
  if (pathname === "/cart") {
    return handleCart(req, res, body);
  }

  // Seller
  if (pathname === "/seller/products" && req.method === "GET") {
    return handleSellerProducts(req, res);
  }
  if (pathname === "/seller/stats" && req.method === "GET") {
    return handleSellerStats(req, res);
  }

  // Admin
  if (pathname === "/admin/users" && req.method === "GET") {
    return handleAdminUsers(req, res);
  }

  return json(res, 404, { error: `Route not found: ${req.method} ${pathname}` });
}

// ─── Playwright route-interception helper ───────────────────────────────────

/**
 * Set up Playwright page route interception so that all /api/* requests
 * are answered by the mock data without ever hitting a real server.
 *
 * @param {import('@playwright/test').Page} page
 */
export async function setupMockRoutes(page) {
  await page.route(/^http:\/\/localhost:\d+\/api\//, async (route) => {
    const request = route.request();
    const method = request.method();
    const rawUrl = request.url();
    const base = "http://localhost";
    const url = new URL(rawUrl, base);

    // Strip the /api prefix that the Vite proxy would normally remove
    const pathname = url.pathname.replace(/^\/api/, "");

    let responseBody;
    let status = 200;

    try {
      if (pathname === "/products" && method === "GET") {
        const products = filterProducts(url);
        responseBody = products;
      } else if (pathname.match(/^\/products\/([^/]+)$/) && method === "GET") {
        const id = pathname.split("/")[2];
        const product = MOCK_PRODUCTS.find((p) => p.id === id);
        if (product) {
          responseBody = product;
        } else {
          status = 404;
          responseBody = { error: "Product not found" };
        }
      } else if (pathname === "/auth/login" && method === "POST") {
        const body = JSON.parse((await request.postData()) ?? "{}");
        const token = MOCK_AUTH_TOKENS[body.email];
        if (!token) {
          status = 401;
          responseBody = { error: "Invalid credentials" };
        } else {
          const userKey = Object.keys(MOCK_USERS).find(
            (k) => MOCK_USERS[k].email === body.email
          );
          responseBody = { token, user: MOCK_USERS[userKey] };
        }
      } else if (pathname === "/auth/register" && method === "POST") {
        const body = JSON.parse((await request.postData()) ?? "{}");
        const newUser = {
          id: `user-${Date.now()}`,
          email: body.email,
          role: body.role ?? "BUYER",
          status: "ACTIVE",
        };
        status = 201;
        responseBody = { token: `mock-jwt-${newUser.id}`, user: newUser };
      } else if (pathname === "/auth/me" && method === "GET") {
        const authHeader = request.headers()["authorization"] ?? "";
        const token = authHeader.replace("Bearer ", "");
        const entry = Object.entries(MOCK_AUTH_TOKENS).find(([, t]) => t === token);
        if (!entry) {
          status = 401;
          responseBody = { error: "Unauthorized" };
        } else {
          const userKey = Object.keys(MOCK_USERS).find(
            (k) => MOCK_USERS[k].email === entry[0]
          );
          responseBody = MOCK_USERS[userKey];
        }
      } else if (pathname === "/orders" && method === "GET") {
        responseBody = MOCK_ORDERS;
      } else if (pathname === "/cart") {
        responseBody = method === "POST" ? { message: "Item added" } : { items: [] };
      } else if (pathname === "/seller/products" && method === "GET") {
        responseBody = MOCK_PRODUCTS;
      } else if (pathname === "/seller/stats" && method === "GET") {
        responseBody = MOCK_SELLER_STATS;
      } else if (pathname === "/admin/users" && method === "GET") {
        responseBody = Object.values(MOCK_USERS);
      } else {
        status = 404;
        responseBody = { error: `Mock: no handler for ${method} ${pathname}` };
      }
    } catch (err) {
      status = 500;
      responseBody = { error: String(err) };
    }

    await route.fulfill({
      status,
      contentType: "application/json",
      body: JSON.stringify(responseBody),
    });
  });
}

function filterProducts(url) {
  const category = url.searchParams.get("category");
  const keyword = url.searchParams.get("keyword");
  let products = [...MOCK_PRODUCTS];
  if (category) products = products.filter((p) => p.category === category);
  if (keyword) {
    const kw = keyword.toLowerCase();
    products = products.filter(
      (p) =>
        p.title.toLowerCase().includes(kw) ||
        (p.description ?? "").toLowerCase().includes(kw)
    );
  }
  return products;
}

// ─── Standalone server entry point ───────────────────────────────────────────

const isMain =
  process.argv[1] &&
  new URL(import.meta.url).pathname === new URL(`file://${process.argv[1]}`).pathname;

if (isMain) {
  const port = parseInt(process.env.MOCK_SERVER_PORT ?? String(DEFAULT_PORT), 10);
  const server = http.createServer(router);
  server.listen(port, () => {
    console.log(`Mock API server listening on http://localhost:${port}`);
  });
}
