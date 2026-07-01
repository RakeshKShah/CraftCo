#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="approve_seller_enables_publishing"
ADMIN_ID="admin-${TEST_ID}-${CASE_SUFFIX}"
ADMIN_EMAIL="${ADMIN_ID}@example.com"
ADMIN_PASSWORD='AdminPass123!'
SELLER_USER_ID="seller-user-${TEST_ID}-${CASE_SUFFIX}"
SELLER_EMAIL="${SELLER_USER_ID}@example.com"
SELLER_PASSWORD='SellerPass123!'
SELLER_ID="seller-${TEST_ID}-${CASE_SUFFIX}"
LOGIN_JSON="/tmp/${TEST_ID}_admin_login_${CASE_SUFFIX}.json"
SELLER_LOGIN_JSON="/tmp/${TEST_ID}_seller_login_${CASE_SUFFIX}.json"
UPDATE_JSON="/tmp/${TEST_ID}_update_${CASE_SUFFIX}.json"
CREATE_JSON="/tmp/${TEST_ID}_create_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/${TEST_ID}_status_${CASE_SUFFIX}.txt"
cleanup() {
  rm -f "$LOGIN_JSON" "$SELLER_LOGIN_JSON" "$UPDATE_JSON" "$CREATE_JSON" "$STATUS_FILE"
  CREATED_PRODUCT_ID="$(jq -r '.id // empty' "$CREATE_JSON" 2>/dev/null || true)"
  if [ -n "${CREATED_PRODUCT_ID:-}" ]; then
    psql "$DATABASE_URL" -c "DELETE FROM products WHERE id='${CREATED_PRODUCT_ID}';" >/dev/null 2>&1 || true
  fi
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id IN ('${SELLER_USER_ID}','${ADMIN_ID}');" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Given — seed an admin and a pending seller account with store profile
ADMIN_HASH='$2b$10$DOWSDR9Kt5I9zQJmlp7iUuY8j5B5P6M8JrIoYNewc19hXtOD87o5e'
SELLER_HASH='$2b$10$DOWSDR9Kt5I9zQJmlp7iUuY8j5B5P6M8JrIoYNewc19hXtOD87o5e'
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${ADMIN_ID}', '${ADMIN_EMAIL}', '${ADMIN_HASH}', 'ADMIN', 'ACTIVE', NOW());
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', '${SELLER_EMAIL}', '${SELLER_HASH}', 'SELLER', 'PENDING', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_ID}', '${SELLER_USER_ID}', 'Pending Store ${CASE_SUFFIX}', 'Pending bio ${CASE_SUFFIX}');
SQL
curl -sS -o "$LOGIN_JSON" -w '%{http_code}' \
  -X POST "$BASE_URL/auth/login" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\"}" > "$STATUS_FILE"
[ "$(cat "$STATUS_FILE")" = "200" ]
ADMIN_TOKEN="$(jq -r '.token' "$LOGIN_JSON")"
[ "$ADMIN_TOKEN" != "null" ]

# When — admin approves the seller, then the seller publishes a product
curl -sS -o "$UPDATE_JSON" -w '%{http_code}' \
  -X PUT "$BASE_URL/admin/sellers/${SELLER_ID}" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  --data '{"status":"ACTIVE"}' > "$STATUS_FILE"

# Then — response is 200, DB status is ACTIVE, and the seller can create a product listing
[ "$(cat "$STATUS_FILE")" = "200" ]
jq -e --arg id "$SELLER_ID" '.id == $id and .status == "ACTIVE"' "$UPDATE_JSON" >/dev/null
[ "$(psql "$DATABASE_URL" -t -A -c "SELECT status FROM users WHERE id='${SELLER_USER_ID}';")" = "ACTIVE" ]
curl -sS -o "$SELLER_LOGIN_JSON" -w '%{http_code}' \
  -X POST "$BASE_URL/auth/login" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\"}" > "$STATUS_FILE"
[ "$(cat "$STATUS_FILE")" = "200" ]
SELLER_TOKEN="$(jq -r '.token' "$SELLER_LOGIN_JSON")"
[ "$SELLER_TOKEN" != "null" ]
curl -sS -o "$CREATE_JSON" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${SELLER_TOKEN}" \
  --data "{\"title\":\"Approved Product ${CASE_SUFFIX}\",\"description\":\"Created after approval\",\"category\":\"tools\",\"price_cents\":1999,\"stock_qty\":4,\"photos\":[]}" > "$STATUS_FILE"
[ "$(cat "$STATUS_FILE")" = "201" ]
jq -e '.title | contains("Approved Product")' "$CREATE_JSON" >/dev/null
CREATED_PRODUCT_ID="$(jq -r '.id' "$CREATE_JSON")"
[ -n "$CREATED_PRODUCT_ID" ]
[ "$CREATED_PRODUCT_ID" != "null" ]
[ "$(psql "$DATABASE_URL" -t -A -c "SELECT visible FROM products WHERE id='${CREATED_PRODUCT_ID}';")" = "t" ]

echo "CODEVALID_TEST_ASSERTION_OK:approve_seller_enables_publishing"

# Cleanup — delete created product plus seeded seller/admin records
