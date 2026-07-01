#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="reactivate_suspended_account"
ADMIN_ID="admin-${TEST_ID}-${CASE_SUFFIX}"
ADMIN_EMAIL="${ADMIN_ID}@example.com"
ADMIN_PASSWORD='AdminPass123!'
SELLER_USER_ID="seller-user-${TEST_ID}-${CASE_SUFFIX}"
SELLER_EMAIL="${SELLER_USER_ID}@example.com"
SELLER_ID="seller-${TEST_ID}-${CASE_SUFFIX}"
PRODUCT_ID_1="product-${TEST_ID}-1-${CASE_SUFFIX}"
PRODUCT_ID_2="product-${TEST_ID}-2-${CASE_SUFFIX}"
LOGIN_JSON="/tmp/${TEST_ID}_login_${CASE_SUFFIX}.json"
UPDATE_JSON="/tmp/${TEST_ID}_update_${CASE_SUFFIX}.json"
MARKET_JSON="/tmp/${TEST_ID}_market_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/${TEST_ID}_status_${CASE_SUFFIX}.txt"
cleanup() {
  rm -f "$LOGIN_JSON" "$UPDATE_JSON" "$MARKET_JSON" "$STATUS_FILE"
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id IN ('${PRODUCT_ID_1}','${PRODUCT_ID_2}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id IN ('${SELLER_USER_ID}','${ADMIN_ID}');" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Given — seed an admin and a suspended seller whose products are currently hidden
ADMIN_HASH='$2b$10$DOWSDR9Kt5I9zQJmlp7iUuY8j5B5P6M8JrIoYNewc19hXtOD87o5e'
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${ADMIN_ID}', '${ADMIN_EMAIL}', '${ADMIN_HASH}', 'ADMIN', 'ACTIVE', NOW());
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', '${SELLER_EMAIL}', '${ADMIN_HASH}', 'SELLER', 'SUSPENDED', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_ID}', '${SELLER_USER_ID}', 'Reactivated Store ${CASE_SUFFIX}', 'Reactivation bio ${CASE_SUFFIX}');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PRODUCT_ID_1}', '${SELLER_ID}', 'Hidden Product 1 ${CASE_SUFFIX}', 'Previously hidden by suspension', 'tools', 2100, 5, '[]', 'ACTIVE', false, NOW()),
  ('${PRODUCT_ID_2}', '${SELLER_ID}', 'Hidden Product 2 ${CASE_SUFFIX}', 'Previously hidden by suspension', 'tools', 2200, 6, '[]', 'ACTIVE', false, NOW());
SQL
curl -sS -o "$LOGIN_JSON" -w '%{http_code}' \
  -X POST "$BASE_URL/auth/login" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\"}" > "$STATUS_FILE"
[ "$(cat "$STATUS_FILE")" = "200" ]
ADMIN_TOKEN="$(jq -r '.token' "$LOGIN_JSON")"
[ "$ADMIN_TOKEN" != "null" ]

# When — admin reactivates the suspended seller
curl -sS -o "$UPDATE_JSON" -w '%{http_code}' \
  -X PUT "$BASE_URL/admin/sellers/${SELLER_ID}" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  --data '{"status":"ACTIVE"}' > "$STATUS_FILE"

# Then — response is 200, seller becomes ACTIVE, and products return to public marketplace visibility
[ "$(cat "$STATUS_FILE")" = "200" ]
jq -e --arg id "$SELLER_ID" '.id == $id and .status == "ACTIVE"' "$UPDATE_JSON" >/dev/null
[ "$(psql "$DATABASE_URL" -t -A -c "SELECT status FROM users WHERE id='${SELLER_USER_ID}';")" = "ACTIVE" ]
[ "$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM products WHERE seller_id='${SELLER_ID}' AND visible = true;")" = "2" ]
curl -sS "$BASE_URL/products" > "$MARKET_JSON"
jq -e --arg p "$PRODUCT_ID_1" '.[] | select(.id == $p and .visible == true)' "$MARKET_JSON" >/dev/null
jq -e --arg p "$PRODUCT_ID_2" '.[] | select(.id == $p and .visible == true)' "$MARKET_JSON" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:reactivate_suspended_account"

# Cleanup — delete seeded products, seller profile, and users
