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

async function setupScenarioMocks(page, scenariosByEndpoint) {
  await page.route("**/api/**", async (route) => {
    const request = route.request();
    const url = new URL(request.url());
    const path = url.pathname.replace(/^\/api/, "") || "/";
    const method = request.method().toUpperCase();

    for (const [endpointKey, scenarioName] of Object.entries(scenariosByEndpoint)) {
      const [expectedMethod, expectedPath] = endpointKey.split(" ");
      if (expectedMethod !== method) continue;
      if (!matchPath(expectedPath, path)) continue;

      const scenario = mockApi[endpointKey]?.[scenarioName];
      if (!scenario) {
        throw new Error(`Missing mock scenario ${scenarioName} for ${endpointKey}`);
      }

      await route.fulfill({
        status: scenario.output.status,
        contentType: "application/json",
        body: JSON.stringify(scenario.output.body),
      });
      return;
    }

    throw new Error(`Unmocked API request: ${method} ${path}`);
  });
}

test("Browse marketplace catalog with available and sold-out products", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder("product_page_browse_available_and_sold_out_products", testInfo);

  await recorder.step("Mock marketplace catalog with both in-stock and sold-out products", async () => {
    await setupScenarioMocks(page, {
      "GET /products": "browse_mixed_stock",
    });
  });

  await recorder.step("Open the marketplace catalog", async () => {
    await page.goto("/");
    await expect(page.getByRole("heading", { name: "Handmade goods from local artisans" })).toBeVisible();
  });

  await recorder.step("Browse the displayed product listings", async () => {
    await expect(page.getByRole("link", { name: /Ocean Wave Mug/i })).toBeVisible();
    await expect(page.getByRole("link", { name: /Sunset Scarf/i })).toBeVisible();
  });

  await recorder.step("Identify a product with available stock", async () => {
    const availableCard = page.getByRole("link", { name: /Ocean Wave Mug/i });
    await expect(availableCard).toContainText("Ocean Wave Mug");
    await expect(availableCard).not.toContainText("Sold out");
  });

  await recorder.step("Identify a product with zero stock", async () => {
    const soldOutCard = page.getByRole("link", { name: /Sunset Scarf/i });
    await expect(soldOutCard).toContainText("Sunset Scarf");
    await expect(soldOutCard).toContainText("Sold out");
  });

  await recorder.step("Verify both stock states remain visible in the catalog", async () => {
    await expect(page.getByText("Ocean Wave Mug")).toBeVisible();
    await expect(page.getByText("Sunset Scarf")).toBeVisible();
    await expect(page.getByText("Sold out")).toBeVisible();
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:product_page_browse_available_and_sold_out_products");
  await recorder.save(testInfo);
});
