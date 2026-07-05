#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="zero-stock-${CASE_SUFFIX}@example.com"
PRODUCT_TITLE="Limited Edition Print ${CASE_SUFFIX}"
REGISTER_RESPONSE="/tmp/zero_stock_creates_sold_out_product_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/zero_stock_creates_sold_out_product_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/zero_stock_creates_sold_out_product_${CASE_SUFFIX}.status"
cleanup_files() {
  rm -f "$REGISTER_RESPONSE" "$RESPONSE_FILE" "$STATUS_FILE"
}
trap cleanup_files EXIT

# Given
curl -sS -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"Password123!\",\"role\":\"SELLER\",\"storeName\":\"Zero Stock Shop ${CASE_SUFFIX}\",\"bio\":\"Art seller\"}" \
  > "$REGISTER_RESPONSE"
TOKEN="$(jq -r '.token' "$REGISTER_RESPONSE")"
USER_ID="$(jq -r '.user.id' "$REGISTER_RESPONSE")"
[ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]
psql "$DATABASE_URL" -c "UPDATE \"User\" SET status = 'ACTIVE' WHERE id = '${USER_ID}';" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  -d "{\"title\":\"${PRODUCT_TITLE}\",\"description\":\"Signed art print\",\"category\":\"ART\",\"price_cents\":12000,\"stock_qty\":0,\"photos\":[\"https://example.com/photo.jpg\"]}" \
  > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "201" ]
jq -e --arg title "$PRODUCT_TITLE" '.title == $title and .status == "SOLD_OUT" and .visible == true and (.id | length > 0)' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:zero_stock_creates_sold_out_product"

# Cleanup
PRODUCT_ID="$(jq -r '.id' "$RESPONSE_FILE")"
if [ -n "$PRODUCT_ID" ] && [ "$PRODUCT_ID" != "null" ]; then
  psql "$DATABASE_URL" -c "DELETE FROM \"Product\" WHERE id = '${PRODUCT_ID}';" >/dev/null
fi
psql "$DATABASE_URL" -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" = '${USER_ID}';" >/dev/null
psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE id = '${USER_ID}';" >/dev/null
