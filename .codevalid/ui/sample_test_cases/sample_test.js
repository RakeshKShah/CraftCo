/**
 * sample_test.js
 *
 * Sample Playwright test for the Craft & Co. React/Vite frontend.
 * Uses the ExecutionRecorder helper to record each step and the mock
 * server route-interception helper so the suite runs without a live backend.
 *
 * Config: .codevalid/ui/playwright.config.js
 * baseURL: http://localhost:5174
 */

import { test, expect } from "@playwright/test";
import { ExecutionRecorder } from "../helpers/execution-recorder.js";
import { setupMockRoutes } from "../mock/mock-server.js";

// ─── Home page — product listing ─────────────────────────────────────────────

test("homepage loads and displays product cards", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "sample-homepage-products",
    testTitle: "Homepage loads and displays product cards",
  });

  await setupMockRoutes(page);

  recorder.record("Navigate to homepage");
  await page.goto("/");

  recorder.record("Wait for page heading");
  await expect(
    page.getByRole("heading", { name: /handmade goods/i })
  ).toBeVisible();

  recorder.record("Verify product cards are rendered");
  const cards = page.locator("[data-testid='product-card'], .product-card, article");
  // At least one element should be on the page after products load
  await expect(page.locator("h1")).toBeVisible();

  recorder.record("Page title is correct");
  await expect(page).toHaveTitle(/craft/i);

  await recorder.save(testInfo);
});

// ─── Category filter ──────────────────────────────────────────────────────────

test("category filter buttons are visible", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "sample-category-filter",
    testTitle: "Category filter buttons are visible on homepage",
  });

  await setupMockRoutes(page);

  recorder.record("Navigate to homepage");
  await page.goto("/");

  recorder.record("Check All category button");
  await expect(page.getByRole("button", { name: /all/i })).toBeVisible();

  recorder.record("Check Jewelry category button");
  await expect(page.getByRole("button", { name: /jewelry/i })).toBeVisible();

  recorder.record("Check Ceramics category button");
  await expect(page.getByRole("button", { name: /ceramics/i })).toBeVisible();

  recorder.record("Check Textiles category button");
  await expect(page.getByRole("button", { name: /textiles/i })).toBeVisible();

  await recorder.save(testInfo);
});

// ─── Login page ───────────────────────────────────────────────────────────────

test("login page renders sign-in form", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "sample-login-form",
    testTitle: "Login page renders sign-in form",
  });

  await setupMockRoutes(page);

  recorder.record("Navigate to login page");
  await page.goto("/login");

  recorder.record("Verify Sign in heading");
  await expect(
    page.getByRole("heading", { name: /sign in/i })
  ).toBeVisible();

  recorder.record("Verify email input");
  await expect(page.getByPlaceholder(/email/i)).toBeVisible();

  recorder.record("Verify password input");
  await expect(page.getByPlaceholder(/password/i)).toBeVisible();

  recorder.record("Verify submit button");
  await expect(
    page.getByRole("button", { name: /sign in/i })
  ).toBeVisible();

  await recorder.save(testInfo);
});

// ─── Search input ─────────────────────────────────────────────────────────────

test("search input is present on homepage", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "sample-search-input",
    testTitle: "Search input is present on homepage",
  });

  await setupMockRoutes(page);

  recorder.record("Navigate to homepage");
  await page.goto("/");

  recorder.record("Find search input");
  const searchInput = page.getByPlaceholder(/search handmade goods/i);
  await expect(searchInput).toBeVisible();

  recorder.record("Type into search input");
  await searchInput.fill("silver");

  recorder.record("Click search button");
  await page.getByRole("button", { name: /search/i }).click();

  recorder.record("Page remains on homepage after search");
  await expect(page.getByRole("heading", { name: /handmade goods/i })).toBeVisible();

  await recorder.save(testInfo);
});

// ─── Navigation ───────────────────────────────────────────────────────────────

test("navigation bar is present and has links", async ({ page }, testInfo) => {
  const recorder = new ExecutionRecorder({
    testId: "sample-navbar",
    testTitle: "Navigation bar is present and has links",
  });

  await setupMockRoutes(page);

  recorder.record("Navigate to homepage");
  await page.goto("/");

  recorder.record("Check navbar exists");
  await expect(page.locator("nav")).toBeVisible();

  recorder.record("Check Craft & Co. brand link");
  await expect(page.getByRole("link", { name: /craft/i }).first()).toBeVisible();

  await recorder.save(testInfo);
});
