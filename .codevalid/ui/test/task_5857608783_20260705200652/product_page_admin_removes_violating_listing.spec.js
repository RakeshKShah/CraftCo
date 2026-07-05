import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../../../../ui_test/helpers/execution-recorder.js";
import mockApi from "../../../../ui_test/mock-api.json" assert { type: "json" };

function normalizePath(pathname) {
  return pathname.replace(/\/$/, "") || "/";
}

function matchPath(pattern, actualPath) {
  if (!pattern.includes(":")) return normalizePath(pattern) === normalizePath(actualPath);
  const patternParts = normalizePath(pattern).split("/");
  const actualParts = normalizePath(actualPath).split("/");
  if (patternParts.length !== actualParts.length) return false;
  return patternParts.every((part, index) => part.startsWith(":") || part === actualParts[index]);
}

async function setupAdminMocks(page) {
  await page.route("**/api/**", async (route) => {
    const request = route.request();
    const url = new URL(request.url());
    const path = url.pathname.replace(/^\/api/, "") || "/";
    const method = request.method().toUpperCase();

    const respond = async (endpointKey, scenarioName) => {
      const scenario = mockApi[endpointKey]?.[scenarioName];
      if (!scenario) throw new Error(`Missing mock scenario ${scenarioName} for ${endpointKey}`);
      await route.fulfill({
        status: scenario.output.status,
        contentType: "application/json",
        body: JSON.stringify(scenario.output.body),
      });
    };

    if (method === "GET" && path === "/auth/me") return respond("GET /auth/me", "admin");
    if (method === "GET" && path === "/admin/sellers") return respond("GET /admin/sellers", "default");
    if (method === "GET" && path === "/admin/products") return respond("GET /admin/products", "violating_listing_present");
    if (method === "DELETE" && matchPath("/admin/products/:id", path)) return respond("DELETE /admin/products/:id", "success");
    if (method === "GET" && path === "/products") return respond("GET /products", "removed_listing_absent");

    throw new Error(`Unmocked API request: ${method} ${path}`);
  });
}

test("Admin removes marketplace listing violating marketplace rules", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder("product_page_admin_removes_violating_listing", testInfo);

  await recorder.step("Mock authenticated admin APIs and violating listing data", async () => {
    await page.addInitScript(() => {
      window.localStorage.setItem("token", "admin-token");
      window.confirm = () => true;
    });
    await setupAdminMocks(page);
  });

  await recorder.step("Open the marketplace listing monitoring area", async () => {
    await page.goto("/admin");
    await expect(page.getByRole("heading", { name: "Admin panel" })).toBeVisible();
    await expect(page.getByRole("heading", { name: "All listings" })).toBeVisible();
  });

  await recorder.step("Locate the violating product listing", async () => {
    const row = page.getByRole("row", { name: /Banned Ivory Necklace/i });
    await expect(row).toBeVisible();
    await expect(row).toContainText("Rule Breakers Market");
    await expect(row).toContainText("ACTIVE");
  });

  await recorder.step("Remove the violating listing from the marketplace", async () => {
    await page.getByRole("row", { name: /Banned Ivory Necklace/i }).getByRole("button", { name: "Remove" }).click();
  });

  await recorder.step("Refresh or revisit the marketplace catalog and verify the listing is gone", async () => {
    await page.goto("/?keyword=Banned%20Ivory%20Necklace");
    await expect(page.getByRole("heading", { name: "Handmade goods from local artisans" })).toBeVisible();
    await expect(page.getByText("No products found.")).toBeVisible();
    await expect(page.getByText("Banned Ivory Necklace")).not.toBeVisible();
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:product_page_admin_removes_violating_listing");
  await recorder.save(testInfo);
});
