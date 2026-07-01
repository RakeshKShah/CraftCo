#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="non_seller_role_cannot_delete_products"
BUYER_EMAIL="buyer-${TEST_ID}-${CASE_SUFFIX}@example.com"
BUYER_PASSWORD="Password123!"
SELLER_EMAIL="owner-${TEST_ID}-${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Password123!"
PRODUCT_ID="prod-${TEST_ID}-${CASE_SUFFIX}"
BUYER_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}_buyer.json"
SELLER_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}_seller.json"
RESPONSE_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$BUYER_FILE" "$SELLER_FILE" "$RESPONSE_FILE" "$STATUS_FILE"; }
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '${PRODUCT_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE email IN ('${BUYER_EMAIL}', '${SELLER_EMAIL}');" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
curl -sS -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"${BUYER_EMAIL}\",\"password\":\"${BUYER_PASSWORD}\",\"role\":\"BUYER\"}" > "$BUYER_FILE"
BUYER_TOKEN="$(jq -r '.token' "$BUYER_FILE")"
[ "$BUYER_TOKEN" != "null" ]
curl -sS -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"Owner Store ${CASE_SUFFIX}\",\"bio\":\"owner setup\"}" > "$SELLER_FILE"
SELLER_ID="$(jq -r '.user.sellerProfile.id' "$SELLER_FILE")"
SELLER_USER_ID="$(jq -r '.user.id' "$SELLER_FILE")"
psql "$DATABASE_URL" -c "UPDATE users SET status = 'ACTIVE' WHERE id = '${SELLER_USER_ID}';" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible) VALUES ('${PRODUCT_ID}', '${SELLER_ID}', 'Buyer Forbidden Product ${CASE_SUFFIX}', 'buyer cannot delete', 'tools', 2400, 2, '[]'::jsonb, 'ACTIVE', true);" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X DELETE \
  "$BASE_URL/products/${PRODUCT_ID}" \
  -H "Authorization: Bearer ${BUYER_TOKEN}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "403" ]
grep -F '"error":"Seller access required"' "$RESPONSE_FILE" >/dev/null
DB_STATE="$(psql "$DATABASE_URL" -t -A -c "SELECT status || '|' || CASE WHEN visible THEN 'true' ELSE 'false' END FROM products WHERE id = '${PRODUCT_ID}';")"
[ "$DB_STATE" = "ACTIVE|true" ]

echo "CODEVALID_TEST_ASSERTION_OK:non_seller_role_cannot_delete_products"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '${PRODUCT_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM users WHERE email IN ('${BUYER_EMAIL}', '${SELLER_EMAIL}');" >/dev/null 2>&1 || true
