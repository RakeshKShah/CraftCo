#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
USER_ID="seller-partial-${CASE_SUFFIX}"
SELLER_ID="profile-partial-${CASE_SUFFIX}"
PRODUCT_ID="prod-partial-${CASE_SUFFIX}"
EMAIL="seller-partial-${CASE_SUFFIX}@example.com"
TOKEN_FILE="/tmp/partial_update_preserves_unspecified_fields_${CASE_SUFFIX}.token"
RESPONSE_FILE="/tmp/partial_update_preserves_unspecified_fields_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/partial_update_preserves_unspecified_fields_${CASE_SUFFIX}.status"
cleanup() {
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id='${PRODUCT_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
  rm -f "$TOKEN_FILE" "$RESPONSE_FILE" "$STATUS_FILE"
}
trap cleanup EXIT

# Given
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('${USER_ID}', '${EMAIL}', 'hash', 'SELLER', 'ACTIVE');"
psql "$DATABASE_URL" -c "INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('${SELLER_ID}', '${USER_ID}', 'Partial Store ${CASE_SUFFIX}', 'Partial bio ${CASE_SUFFIX}');"
psql "$DATABASE_URL" -c "INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible) VALUES ('${PRODUCT_ID}', '${SELLER_ID}', 'Original Title', 'Original desc', 'BOOKS', 2500, 3, '[\"photo1.jpg\"]'::jsonb, 'ACTIVE', true);"
node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"SELLER",status:"ACTIVE"}, process.env.JWT_SECRET));' "$USER_ID" "$EMAIL" > "$TOKEN_FILE"
TOKEN="$(cat "$TOKEN_FILE")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X PUT "$BASE_URL/products/${PRODUCT_ID}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  --data '{"stock_qty":0}' > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
grep -F '"id":"'"$PRODUCT_ID"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"title":"Original Title"' "$RESPONSE_FILE" >/dev/null
grep -F '"description":"Original desc"' "$RESPONSE_FILE" >/dev/null
grep -F '"category":"BOOKS"' "$RESPONSE_FILE" >/dev/null
grep -F '"priceCents":2500' "$RESPONSE_FILE" >/dev/null
grep -F '"stockQty":0' "$RESPONSE_FILE" >/dev/null
grep -F '"photos":["photo1.jpg"]' "$RESPONSE_FILE" >/dev/null
DB_ROW="$(psql "$DATABASE_URL" -t -A -c "SELECT title || '|' || description || '|' || category || '|' || price_cents::text || '|' || stock_qty::text || '|' || (photos #>> '{}') FROM products WHERE id='${PRODUCT_ID}';")"
[ "$DB_ROW" = 'Original Title|Original desc|BOOKS|2500|0|photo1.jpg' ]
DB_STATUS="$(psql "$DATABASE_URL" -t -A -c "SELECT status FROM products WHERE id='${PRODUCT_ID}';")"
[ "$DB_STATUS" = 'SOLD_OUT' ]
echo "CODEVALID_TEST_ASSERTION_OK:partial_update_preserves_unspecified_fields"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM products WHERE id='${PRODUCT_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
