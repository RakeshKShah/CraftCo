#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
USER_ID="user-soldout-${CASE_SUFFIX}"
SELLER_ID="seller-profile-soldout-${CASE_SUFFIX}"
EMAIL="soldout-${CASE_SUFFIX}@example.com"
TOKEN_FILE="/tmp/product_stock_zero_sets_status_sold_out_${CASE_SUFFIX}.token"
RESPONSE_FILE="/tmp/product_stock_zero_sets_status_sold_out_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/product_stock_zero_sets_status_sold_out_${CASE_SUFFIX}.status"
PRODUCT_ID=""
cleanup() {
  if [ -n "$PRODUCT_ID" ]; then
    psql "$DATABASE_URL" -c "DELETE FROM products WHERE id='${PRODUCT_ID}';" >/dev/null 2>&1 || true
  fi
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE seller_id='${SELLER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
  rm -f "$TOKEN_FILE" "$RESPONSE_FILE" "$STATUS_FILE"
}
trap cleanup EXIT

# Given
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('${USER_ID}', '${EMAIL}', 'hash', 'SELLER', 'ACTIVE');"
psql "$DATABASE_URL" -c "INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('${SELLER_ID}', '${USER_ID}', 'Sold Out Store ${CASE_SUFFIX}', 'Art seller ${CASE_SUFFIX}');"
node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"SELLER",status:"ACTIVE"}, process.env.JWT_SECRET));' "$USER_ID" "$EMAIL" > "$TOKEN_FILE"
TOKEN="$(cat "$TOKEN_FILE")"
TITLE="Out-of-Stock Poster ${CASE_SUFFIX}"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  --data "{\"title\":\"${TITLE}\",\"description\":\"Art print\",\"category\":\"ART\",\"price_cents\":3000,\"stock_qty\":0,\"photos\":[\"https://example.com/poster.png\"]}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "201" ]
grep -F '"title":"'"$TITLE"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"stockQty":0' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"SOLD_OUT"' "$RESPONSE_FILE" >/dev/null
grep -F '"visible":true' "$RESPONSE_FILE" >/dev/null
PRODUCT_ID="$(sed -n 's/.*"id":"\([^"]*\)".*/\1/p' "$RESPONSE_FILE" | head -n 1)"
[ -n "$PRODUCT_ID" ]
DB_COUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM products WHERE id='${PRODUCT_ID}' AND seller_id='${SELLER_ID}' AND visible=true AND status='SOLD_OUT';")"
[ "$DB_COUNT" = "1" ]
echo "CODEVALID_TEST_ASSERTION_OK:product_stock_zero_sets_status_sold_out"

# Cleanup
if [ -n "$PRODUCT_ID" ]; then
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id='${PRODUCT_ID}';" >/dev/null 2>&1 || true
fi
psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
