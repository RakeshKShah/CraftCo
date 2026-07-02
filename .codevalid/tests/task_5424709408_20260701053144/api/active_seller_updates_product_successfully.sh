#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
USER_ID="seller-active-${CASE_SUFFIX}"
SELLER_ID="profile-active-${CASE_SUFFIX}"
PRODUCT_ID="prod-active-${CASE_SUFFIX}"
EMAIL="seller-active-${CASE_SUFFIX}@example.com"
TOKEN_FILE="/tmp/active_seller_updates_product_successfully_${CASE_SUFFIX}.token"
RESPONSE_FILE="/tmp/active_seller_updates_product_successfully_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/active_seller_updates_product_successfully_${CASE_SUFFIX}.status"
cleanup() {
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id='${PRODUCT_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
  rm -f "$TOKEN_FILE" "$RESPONSE_FILE" "$STATUS_FILE"
}
trap cleanup EXIT

# Given
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('${USER_ID}', '${EMAIL}', 'hash', 'SELLER', 'ACTIVE');"
psql "$DATABASE_URL" -c "INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('${SELLER_ID}', '${USER_ID}', 'Active Store ${CASE_SUFFIX}', 'Active bio ${CASE_SUFFIX}');"
psql "$DATABASE_URL" -c "INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible) VALUES ('${PRODUCT_ID}', '${SELLER_ID}', 'Old Title', 'Old desc', 'ELECTRONICS', 1000, 5, '[]'::jsonb, 'ACTIVE', true);"
node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"SELLER",status:"ACTIVE"}, process.env.JWT_SECRET));' "$USER_ID" "$EMAIL" > "$TOKEN_FILE"
TOKEN="$(cat "$TOKEN_FILE")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X PUT "$BASE_URL/products/${PRODUCT_ID}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  --data '{"title":"New Title","price_cents":1500,"stock_qty":10}' > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
grep -F '"id":"'"$PRODUCT_ID"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"title":"New Title"' "$RESPONSE_FILE" >/dev/null
grep -F '"description":"Old desc"' "$RESPONSE_FILE" >/dev/null
grep -F '"category":"ELECTRONICS"' "$RESPONSE_FILE" >/dev/null
grep -F '"priceCents":1500' "$RESPONSE_FILE" >/dev/null
grep -F '"stockQty":10' "$RESPONSE_FILE" >/dev/null
DB_ROW="$(psql "$DATABASE_URL" -t -A -c "SELECT title || '|' || description || '|' || category || '|' || price_cents::text || '|' || stock_qty::text FROM products WHERE id='${PRODUCT_ID}' AND seller_id='${SELLER_ID}';")"
[ "$DB_ROW" = 'New Title|Old desc|ELECTRONICS|1500|10' ]
echo "CODEVALID_TEST_ASSERTION_OK:active_seller_updates_product_successfully"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM products WHERE id='${PRODUCT_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
