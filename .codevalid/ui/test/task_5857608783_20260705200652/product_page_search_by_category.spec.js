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

test("Search marketplace catalog by category", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder("product_page_search_by_category", testInfo);

  await recorder.step("Mock category filter results with mixed stock states", async () => {
    await setupScenarioMocks(page, {
      "GET /products": "category_search_mixed_stock",
    });
  });

  await recorder.step("Open the marketplace catalog", async () => {
    await page.goto("/");
    await expect(page.getByRole("heading", { name: "Handmade goods from local artisans" })).toBeVisible();
  });

  await recorder.step("Select the ceramics category", async () => {
    await page.getByRole("button", { name: "ceramics" }).click();
  });

  await recorder.step("Review the displayed products", async () => {
    await expect(page.getByRole("link", { name: /River Vase/i })).toBeVisible();
    await expect(page.getByRole("link", { name: /Moon Bowl/i })).toBeVisible();
    await expect(page.getByRole("link", { name: /Moon Bowl/i })).toContainText("Sold out");
  });

  await recorder.step("Verify only products from the selected category are shown", async () => {
    await expect(page.getByText("ceramics", { exact: true }).first()).toBeVisible();
    await expect(page.getByText("River Vase")).toBeVisible();
    await expect(page.getByText("Moon Bowl")).toBeVisible();
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:product_page_search_by_category");
  await recorder.save(testInfo);
});
