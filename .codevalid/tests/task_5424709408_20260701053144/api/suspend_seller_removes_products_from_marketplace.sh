#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="suspend_seller_removes_products_from_marketplace"
ADMIN_ID="admin-${TEST_ID}-${CASE_SUFFIX}"
ADMIN_EMAIL="${ADMIN_ID}@example.com"
ADMIN_PASSWORD='AdminPass123!'
SELLER_USER_ID="seller-user-${TEST_ID}-${CASE_SUFFIX}"
SELLER_ID="seller-live789-${CASE_SUFFIX}"
PRODUCT_ID_1="live-prod-1-${CASE_SUFFIX}"
PRODUCT_ID_2="live-prod-2-${CASE_SUFFIX}"
PRODUCT_ID_3="live-prod-3-${CASE_SUFFIX}"
PRODUCT_ID_4="live-prod-4-${CASE_SUFFIX}"
PRODUCT_ID_5="live-prod-5-${CASE_SUFFIX}"
LOGIN_JSON="/tmp/${TEST_ID}_login_${CASE_SUFFIX}.json"
UPDATE_JSON="/tmp/${TEST_ID}_update_${CASE_SUFFIX}.json"
MARKET_JSON="/tmp/${TEST_ID}_market_${CASE_SUFFIX}.json"
ADMIN_JSON="/tmp/${TEST_ID}_admin_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/${TEST_ID}_status_${CASE_SUFFIX}.txt"
cleanup() {
  rm -f "$LOGIN_JSON" "$UPDATE_JSON" "$MARKET_JSON" "$ADMIN_JSON" "$STATUS_FILE"
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id IN ('${PRODUCT_ID_1}','${PRODUCT_ID_2}','${PRODUCT_ID_3}','${PRODUCT_ID_4}','${PRODUCT_ID_5}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id IN ('${SELLER_USER_ID}','${ADMIN_ID}');" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Given — seed an active seller with five buyer-visible products and an admin
HASH='$2b$10$DOWSDR9Kt5I9zQJmlp7iUuY8j5B5P6M8JrIoYNewc19hXtOD87o5e'
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${ADMIN_ID}', '${ADMIN_EMAIL}', '${HASH}', 'ADMIN', 'ACTIVE', NOW());
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', 'seller-${TEST_ID}-${CASE_SUFFIX}@example.com', '${HASH}', 'SELLER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_ID}', '${SELLER_USER_ID}', 'Live Store ${CASE_SUFFIX}', 'Marketplace seller');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PRODUCT_ID_1}', '${SELLER_ID}', 'Live Product 1 ${CASE_SUFFIX}', 'Visible product 1', 'tools', 1000, 1, '[]', 'ACTIVE', true, NOW()),
  ('${PRODUCT_ID_2}', '${SELLER_ID}', 'Live Product 2 ${CASE_SUFFIX}', 'Visible product 2', 'tools', 1100, 2, '[]', 'ACTIVE', true, NOW()),
  ('${PRODUCT_ID_3}', '${SELLER_ID}', 'Live Product 3 ${CASE_SUFFIX}', 'Visible product 3', 'tools', 1200, 3, '[]', 'ACTIVE', true, NOW()),
  ('${PRODUCT_ID_4}', '${SELLER_ID}', 'Live Product 4 ${CASE_SUFFIX}', 'Visible product 4', 'tools', 1300, 4, '[]', 'ACTIVE', true, NOW()),
  ('${PRODUCT_ID_5}', '${SELLER_ID}', 'Live Product 5 ${CASE_SUFFIX}', 'Visible product 5', 'tools', 1400, 5, '[]', 'ACTIVE', true, NOW());
SQL
curl -sS -o "$LOGIN_JSON" -w '%{http_code}' \
  -X POST "$BASE_URL/auth/login" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\"}" > "$STATUS_FILE"
[ "$(cat "$STATUS_FILE")" = "200" ]
ADMIN_TOKEN="$(jq -r '.token' "$LOGIN_JSON")"
[ "$ADMIN_TOKEN" != "null" ]

# When — admin suspends the seller
curl -sS -o "$UPDATE_JSON" -w '%{http_code}' \
  -X PUT "$BASE_URL/admin/sellers/${SELLER_ID}" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  --data '{"status":"SUSPENDED"}' > "$STATUS_FILE"

# Then — all products disappear from buyer marketplace immediately while admin still sees the seller with product_count 5
[ "$(cat "$STATUS_FILE")" = "200" ]
jq -e --arg id "$SELLER_ID" '.id == $id and .status == "SUSPENDED"' "$UPDATE_JSON" >/dev/null
[ "$(psql "$DATABASE_URL" -t -A -c "SELECT status FROM users WHERE id='${SELLER_USER_ID}';")" = "SUSPENDED" ]
[ "$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM products WHERE seller_id='${SELLER_ID}' AND visible = false;")" = "5" ]
curl -sS "$BASE_URL/products" > "$MARKET_JSON"
if jq -e --arg p "$PRODUCT_ID_1" '.[] | select(.id == $p)' "$MARKET_JSON" >/dev/null; then exit 1; fi
if jq -e --arg p "$PRODUCT_ID_2" '.[] | select(.id == $p)' "$MARKET_JSON" >/dev/null; then exit 1; fi
if jq -e --arg p "$PRODUCT_ID_3" '.[] | select(.id == $p)' "$MARKET_JSON" >/dev/null; then exit 1; fi
if jq -e --arg p "$PRODUCT_ID_4" '.[] | select(.id == $p)' "$MARKET_JSON" >/dev/null; then exit 1; fi
if jq -e --arg p "$PRODUCT_ID_5" '.[] | select(.id == $p)' "$MARKET_JSON" >/dev/null; then exit 1; fi
curl -sS -H "Authorization: Bearer ${ADMIN_TOKEN}" "$BASE_URL/admin/sellers" > "$ADMIN_JSON"
jq -e --arg id "$SELLER_ID" '.[] | select(.id == $id and .status == "SUSPENDED" and .product_count == 5)' "$ADMIN_JSON" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:suspend_seller_removes_products_from_marketplace"

# Cleanup — remove seeded products, seller, and admin
