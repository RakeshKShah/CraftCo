#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="authenticated_active_seller_deletes_own_product"
USER_EMAIL="seller-${TEST_ID}-${CASE_SUFFIX}@example.com"
USER_PASSWORD="Password123!"
STORE_NAME="Store ${CASE_SUFFIX}"
PRODUCT_ID="prod-${TEST_ID}-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.status"
REGISTER_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}_register.json"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE" "$REGISTER_FILE"; }
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '${PRODUCT_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE email = '${USER_EMAIL}';" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
curl -sS -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"${USER_EMAIL}\",\"password\":\"${USER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\",\"bio\":\"active seller deletion test ${CASE_SUFFIX}\"}" \
  > "$REGISTER_FILE"
TOKEN="$(jq -r '.token' "$REGISTER_FILE")"
USER_ID="$(jq -r '.user.id' "$REGISTER_FILE")"
SELLER_ID="$(jq -r '.user.sellerProfile.id' "$REGISTER_FILE")"
[ "$TOKEN" != "null" ]
psql "$DATABASE_URL" -c "UPDATE users SET status = 'ACTIVE' WHERE id = '${USER_ID}';" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible) VALUES ('${PRODUCT_ID}', '${SELLER_ID}', 'Delete Me ${CASE_SUFFIX}', 'delete target', 'tools', 2500, 3, '[]'::jsonb, 'ACTIVE', true);" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X DELETE \
  "$BASE_URL/products/${PRODUCT_ID}" \
  -H "Authorization: Bearer ${TOKEN}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
grep -F '"success":true' "$RESPONSE_FILE" >/dev/null
DB_STATE="$(psql "$DATABASE_URL" -t -A -c "SELECT status || '|' || CASE WHEN visible THEN 'true' ELSE 'false' END FROM products WHERE id = '${PRODUCT_ID}';")"
[ "$DB_STATE" = "REMOVED|false" ]

echo "CODEVALID_TEST_ASSERTION_OK:authenticated_active_seller_deletes_own_product"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '${PRODUCT_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM users WHERE email = '${USER_EMAIL}';" >/dev/null 2>&1 || true
