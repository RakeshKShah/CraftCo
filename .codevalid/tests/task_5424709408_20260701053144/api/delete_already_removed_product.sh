#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="delete_already_removed_product"
USER_EMAIL="seller-${TEST_ID}-${CASE_SUFFIX}@example.com"
USER_PASSWORD="Password123!"
PRODUCT_ID="prod-${TEST_ID}-${CASE_SUFFIX}"
REGISTER_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}_register.json"
RESPONSE_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$REGISTER_FILE" "$RESPONSE_FILE" "$STATUS_FILE"; }
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '${PRODUCT_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE email = '${USER_EMAIL}';" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
curl -sS -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"${USER_EMAIL}\",\"password\":\"${USER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"Removed Store ${CASE_SUFFIX}\",\"bio\":\"removed product test\"}" \
  > "$REGISTER_FILE"
TOKEN="$(jq -r '.token' "$REGISTER_FILE")"
USER_ID="$(jq -r '.user.id' "$REGISTER_FILE")"
SELLER_ID="$(jq -r '.user.sellerProfile.id' "$REGISTER_FILE")"
[ "$TOKEN" != "null" ]
psql "$DATABASE_URL" -c "UPDATE users SET status = 'ACTIVE' WHERE id = '${USER_ID}';" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible) VALUES ('${PRODUCT_ID}', '${SELLER_ID}', 'Already Removed ${CASE_SUFFIX}', 'already removed product', 'tools', 1600, 1, '[]'::jsonb, 'REMOVED', false);" >/dev/null

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

echo "CODEVALID_TEST_ASSERTION_OK:delete_already_removed_product"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '${PRODUCT_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM users WHERE email = '${USER_EMAIL}';" >/dev/null 2>&1 || true
