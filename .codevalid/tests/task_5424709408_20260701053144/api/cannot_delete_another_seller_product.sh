#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="cannot_delete_another_seller_product"
ACTOR_EMAIL="actor-${TEST_ID}-${CASE_SUFFIX}@example.com"
OWNER_EMAIL="owner-${TEST_ID}-${CASE_SUFFIX}@example.com"
USER_PASSWORD="Password123!"
PRODUCT_ID="prod-${TEST_ID}-${CASE_SUFFIX}"
ACTOR_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}_actor.json"
OWNER_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}_owner.json"
RESPONSE_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$ACTOR_FILE" "$OWNER_FILE" "$RESPONSE_FILE" "$STATUS_FILE"; }
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '${PRODUCT_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE email IN ('${ACTOR_EMAIL}', '${OWNER_EMAIL}');" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
curl -sS -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"${ACTOR_EMAIL}\",\"password\":\"${USER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"Actor Store ${CASE_SUFFIX}\",\"bio\":\"actor\"}" \
  > "$ACTOR_FILE"
ACTOR_TOKEN="$(jq -r '.token' "$ACTOR_FILE")"
ACTOR_USER_ID="$(jq -r '.user.id' "$ACTOR_FILE")"
[ "$ACTOR_TOKEN" != "null" ]
psql "$DATABASE_URL" -c "UPDATE users SET status = 'ACTIVE' WHERE id = '${ACTOR_USER_ID}';" >/dev/null
curl -sS -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"${OWNER_EMAIL}\",\"password\":\"${USER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"Owner Store ${CASE_SUFFIX}\",\"bio\":\"owner\"}" \
  > "$OWNER_FILE"
OWNER_USER_ID="$(jq -r '.user.id' "$OWNER_FILE")"
OWNER_SELLER_ID="$(jq -r '.user.sellerProfile.id' "$OWNER_FILE")"
psql "$DATABASE_URL" -c "UPDATE users SET status = 'ACTIVE' WHERE id = '${OWNER_USER_ID}';" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible) VALUES ('${PRODUCT_ID}', '${OWNER_SELLER_ID}', 'Other Seller ${CASE_SUFFIX}', 'other seller product', 'tools', 2450, 5, '[]'::jsonb, 'ACTIVE', true);" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X DELETE \
  "$BASE_URL/products/${PRODUCT_ID}" \
  -H "Authorization: Bearer ${ACTOR_TOKEN}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "404" ]
grep -F '"error":"Product not found"' "$RESPONSE_FILE" >/dev/null
DB_OWNER="$(psql "$DATABASE_URL" -t -A -c "SELECT seller_id || '|' || status || '|' || CASE WHEN visible THEN 'true' ELSE 'false' END FROM products WHERE id = '${PRODUCT_ID}';")"
[ "$DB_OWNER" = "${OWNER_SELLER_ID}|ACTIVE|true" ]

echo "CODEVALID_TEST_ASSERTION_OK:cannot_delete_another_seller_product"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '${PRODUCT_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM users WHERE email IN ('${ACTOR_EMAIL}', '${OWNER_EMAIL}');" >/dev/null 2>&1 || true
