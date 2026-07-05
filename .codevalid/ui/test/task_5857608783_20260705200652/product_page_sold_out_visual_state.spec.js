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

test("Sold-out products display greyed-out state and sold out label", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder("product_page_sold_out_visual_state", testInfo);

  await recorder.step("Mock marketplace catalog with a zero-stock product", async () => {
    await setupScenarioMocks(page, {
      "GET /products": "sold_out_visible",
    });
  });

  await recorder.step("Open the marketplace catalog", async () => {
    await page.goto("/");
    await expect(page.getByRole("heading", { name: "Handmade goods from local artisans" })).toBeVisible();
  });

  await recorder.step("Locate the zero-stock product listing", async () => {
    const soldOutCard = page.getByRole("link", { name: /Sunset Scarf/i });
    await expect(soldOutCard).toBeVisible();
    await expect(soldOutCard).toContainText("Sunset Scarf");
  });

  await recorder.step("Observe the sold-out styling and status label", async () => {
    const soldOutCard = page.getByRole("link", { name: /Sunset Scarf/i });
    await expect(soldOutCard).toContainText("Sold out");
    await expect(soldOutCard).toHaveClass(/opacity-60/);
    await expect(soldOutCard).toHaveClass(/grayscale/);
  });

  await recorder.step("Verify the sold-out product remains visible", async () => {
    await expect(page.getByText("Sold out")).toBeVisible();
    await expect(page.getByText("Sunset Scarf")).toBeVisible();
  });

  console.log("CODEVALID_TEST_ASSERTION_OK:product_page_sold_out_visual_state");
  await recorder.save(testInfo);
});
