#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="seller_cannot_delete_other_seller_product"
ACTOR_EMAIL="actor-${TEST_ID}-${CASE_SUFFIX}@example.com"
ACTOR_PASSWORD="Password123!"
OWNER_EMAIL="owner-${TEST_ID}-${CASE_SUFFIX}@example.com"
OWNER_PASSWORD="Password123!"
PRODUCT_ID="prod-${TEST_ID}-${CASE_SUFFIX}"
ACTOR_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}_actor.json"
OWNER_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}_owner.json"
LOGIN_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}_login.json"
RESPONSE_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$ACTOR_FILE" "$OWNER_FILE" "$LOGIN_FILE" "$RESPONSE_FILE" "$STATUS_FILE"; }
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '${PRODUCT_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE email IN ('${ACTOR_EMAIL}', '${OWNER_EMAIL}');" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
curl -sS -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"${ACTOR_EMAIL}\",\"password\":\"${ACTOR_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"Actor Store ${CASE_SUFFIX}\",\"bio\":\"actor\"}" > "$ACTOR_FILE"
ACTOR_USER_ID="$(jq -r '.user.id' "$ACTOR_FILE")"
psql "$DATABASE_URL" -c "UPDATE users SET status = 'ACTIVE' WHERE id = '${ACTOR_USER_ID}';" >/dev/null
curl -sS -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"${OWNER_EMAIL}\",\"password\":\"${OWNER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"Owner Store ${CASE_SUFFIX}\",\"bio\":\"owner\"}" > "$OWNER_FILE"
OWNER_USER_ID="$(jq -r '.user.id' "$OWNER_FILE")"
OWNER_SELLER_ID="$(jq -r '.user.sellerProfile.id' "$OWNER_FILE")"
psql "$DATABASE_URL" -c "UPDATE users SET status = 'ACTIVE' WHERE id = '${OWNER_USER_ID}';" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible) VALUES ('${PRODUCT_ID}', '${OWNER_SELLER_ID}', 'Other Seller Product ${CASE_SUFFIX}', 'belongs to another seller', 'tools', 2600, 5, '[]'::jsonb, 'ACTIVE', true);" >/dev/null
curl -sS -X POST "$BASE_URL/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"${ACTOR_EMAIL}\",\"password\":\"${ACTOR_PASSWORD}\"}" > "$LOGIN_FILE"
ACTOR_TOKEN="$(jq -r '.token' "$LOGIN_FILE")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X DELETE \
  "$BASE_URL/products/${PRODUCT_ID}" \
  -H "Authorization: Bearer ${ACTOR_TOKEN}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "404" ]
grep -F '"error":"Product not found"' "$RESPONSE_FILE" >/dev/null
DB_STATE="$(psql "$DATABASE_URL" -t -A -c "SELECT status || '|' || CASE WHEN visible THEN 'true' ELSE 'false' END FROM products WHERE id = '${PRODUCT_ID}';")"
[ "$DB_STATE" = "ACTIVE|true" ]

echo "CODEVALID_TEST_ASSERTION_OK:seller_cannot_delete_other_seller_product"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '${PRODUCT_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM users WHERE email IN ('${ACTOR_EMAIL}', '${OWNER_EMAIL}');" >/dev/null 2>&1 || true
