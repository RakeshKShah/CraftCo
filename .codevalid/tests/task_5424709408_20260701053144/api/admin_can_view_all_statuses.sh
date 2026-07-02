#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="admin_can_view_all_statuses"
ADMIN_ID="admin-${TEST_ID}-${CASE_SUFFIX}"
ADMIN_EMAIL="${ADMIN_ID}@example.com"
ADMIN_PASSWORD='AdminPass123!'
PENDING_USER_ID="seller-pending-user-${CASE_SUFFIX}"
ACTIVE_USER_ID="seller-active-user-${CASE_SUFFIX}"
SUSPENDED_USER_ID="seller-suspended-user-${CASE_SUFFIX}"
PENDING_SELLER_ID="seller-pending001-${CASE_SUFFIX}"
ACTIVE_SELLER_ID="seller-active002-${CASE_SUFFIX}"
SUSPENDED_SELLER_ID="seller-suspended003-${CASE_SUFFIX}"
PENDING_PRODUCT_ID="pending-product-${CASE_SUFFIX}"
ACTIVE_PRODUCT_ID="active-product-${CASE_SUFFIX}"
SUSPENDED_PRODUCT_ID="suspended-product-${CASE_SUFFIX}"
LOGIN_JSON="/tmp/${TEST_ID}_login_${CASE_SUFFIX}.json"
RESP1_JSON="/tmp/${TEST_ID}_resp1_${CASE_SUFFIX}.json"
RESP2_JSON="/tmp/${TEST_ID}_resp2_${CASE_SUFFIX}.json"
RESP3_JSON="/tmp/${TEST_ID}_resp3_${CASE_SUFFIX}.json"
ADMIN_JSON="/tmp/${TEST_ID}_admin_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/${TEST_ID}_status_${CASE_SUFFIX}.txt"
cleanup() {
  rm -f "$LOGIN_JSON" "$RESP1_JSON" "$RESP2_JSON" "$RESP3_JSON" "$ADMIN_JSON" "$STATUS_FILE"
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id IN ('${PENDING_PRODUCT_ID}','${ACTIVE_PRODUCT_ID}','${SUSPENDED_PRODUCT_ID}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id IN ('${PENDING_SELLER_ID}','${ACTIVE_SELLER_ID}','${SUSPENDED_SELLER_ID}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id IN ('${PENDING_USER_ID}','${ACTIVE_USER_ID}','${SUSPENDED_USER_ID}','${ADMIN_ID}');" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Given — seed admin plus sellers in PENDING, ACTIVE, and SUSPENDED states with representative products
HASH='$2b$10$DOWSDR9Kt5I9zQJmlp7iUuY8j5B5P6M8JrIoYNewc19hXtOD87o5e'
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${ADMIN_ID}', '${ADMIN_EMAIL}', '${HASH}', 'ADMIN', 'ACTIVE', NOW());
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES
  ('${PENDING_USER_ID}', 'pending-${CASE_SUFFIX}@example.com', '${HASH}', 'SELLER', 'PENDING', NOW()),
  ('${ACTIVE_USER_ID}', 'active-${CASE_SUFFIX}@example.com', '${HASH}', 'SELLER', 'ACTIVE', NOW()),
  ('${SUSPENDED_USER_ID}', 'suspended-${CASE_SUFFIX}@example.com', '${HASH}', 'SELLER', 'SUSPENDED', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES
  ('${PENDING_SELLER_ID}', '${PENDING_USER_ID}', 'Pending Store ${CASE_SUFFIX}', 'Pending bio'),
  ('${ACTIVE_SELLER_ID}', '${ACTIVE_USER_ID}', 'Active Store ${CASE_SUFFIX}', 'Active bio'),
  ('${SUSPENDED_SELLER_ID}', '${SUSPENDED_USER_ID}', 'Suspended Store ${CASE_SUFFIX}', 'Suspended bio');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PENDING_PRODUCT_ID}', '${PENDING_SELLER_ID}', 'Pending Product ${CASE_SUFFIX}', 'Pending hidden product', 'tools', 1000, 1, '[]', 'ACTIVE', false, NOW()),
  ('${ACTIVE_PRODUCT_ID}', '${ACTIVE_SELLER_ID}', 'Active Product ${CASE_SUFFIX}', 'Active visible product', 'tools', 2000, 2, '[]', 'ACTIVE', true, NOW()),
  ('${SUSPENDED_PRODUCT_ID}', '${SUSPENDED_SELLER_ID}', 'Suspended Product ${CASE_SUFFIX}', 'Suspended hidden product', 'tools', 3000, 3, '[]', 'ACTIVE', false, NOW());
SQL
curl -sS -o "$LOGIN_JSON" -w '%{http_code}' \
  -X POST "$BASE_URL/auth/login" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\"}" > "$STATUS_FILE"
[ "$(cat "$STATUS_FILE")" = "200" ]
ADMIN_TOKEN="$(jq -r '.token' "$LOGIN_JSON")"
[ "$ADMIN_TOKEN" != "null" ]

# When — admin updates sellers across three different starting statuses
curl -sS -o "$RESP1_JSON" -w '%{http_code}' \
  -X PUT "$BASE_URL/admin/sellers/${PENDING_SELLER_ID}" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  --data '{"status":"ACTIVE"}' > "$STATUS_FILE"
[ "$(cat "$STATUS_FILE")" = "200" ]
curl -sS -o "$RESP2_JSON" -w '%{http_code}' \
  -X PUT "$BASE_URL/admin/sellers/${ACTIVE_SELLER_ID}" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  --data '{"status":"SUSPENDED"}' > "$STATUS_FILE"
[ "$(cat "$STATUS_FILE")" = "200" ]
curl -sS -o "$RESP3_JSON" -w '%{http_code}' \
  -X PUT "$BASE_URL/admin/sellers/${SUSPENDED_SELLER_ID}" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  --data '{"status":"ACTIVE"}' > "$STATUS_FILE"

# Then — all updates succeed and admin listing reflects each final status and product count
[ "$(cat "$STATUS_FILE")" = "200" ]
jq -e --arg id "$PENDING_SELLER_ID" '.id == $id and .status == "ACTIVE"' "$RESP1_JSON" >/dev/null
jq -e --arg id "$ACTIVE_SELLER_ID" '.id == $id and .status == "SUSPENDED"' "$RESP2_JSON" >/dev/null
jq -e --arg id "$SUSPENDED_SELLER_ID" '.id == $id and .status == "ACTIVE"' "$RESP3_JSON" >/dev/null
[ "$(psql "$DATABASE_URL" -t -A -c "SELECT status FROM users WHERE id='${PENDING_USER_ID}';")" = "ACTIVE" ]
[ "$(psql "$DATABASE_URL" -t -A -c "SELECT status FROM users WHERE id='${ACTIVE_USER_ID}';")" = "SUSPENDED" ]
[ "$(psql "$DATABASE_URL" -t -A -c "SELECT status FROM users WHERE id='${SUSPENDED_USER_ID}';")" = "ACTIVE" ]
[ "$(psql "$DATABASE_URL" -t -A -c "SELECT visible FROM products WHERE id='${PENDING_PRODUCT_ID}';")" = "t" ]
[ "$(psql "$DATABASE_URL" -t -A -c "SELECT visible FROM products WHERE id='${ACTIVE_PRODUCT_ID}';")" = "f" ]
[ "$(psql "$DATABASE_URL" -t -A -c "SELECT visible FROM products WHERE id='${SUSPENDED_PRODUCT_ID}';")" = "t" ]
curl -sS -H "Authorization: Bearer ${ADMIN_TOKEN}" "$BASE_URL/admin/sellers" > "$ADMIN_JSON"
jq -e --arg id "$PENDING_SELLER_ID" '.[] | select(.id == $id and .status == "ACTIVE" and .product_count == 1)' "$ADMIN_JSON" >/dev/null
jq -e --arg id "$ACTIVE_SELLER_ID" '.[] | select(.id == $id and .status == "SUSPENDED" and .product_count == 1)' "$ADMIN_JSON" >/dev/null
jq -e --arg id "$SUSPENDED_SELLER_ID" '.[] | select(.id == $id and .status == "ACTIVE" and .product_count == 1)' "$ADMIN_JSON" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:admin_can_view_all_statuses"

# Cleanup — remove seeded sellers, products, and admin
