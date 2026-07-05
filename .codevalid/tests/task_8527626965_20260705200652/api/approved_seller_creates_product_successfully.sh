#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="approved-seller-${CASE_SUFFIX}@example.com"
STORE_NAME="Approved Shop ${CASE_SUFFIX}"
PRODUCT_TITLE="Handmade Ceramic Vase ${CASE_SUFFIX}"
REGISTER_RESPONSE="/tmp/approved_seller_creates_product_successfully_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/approved_seller_creates_product_successfully_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/approved_seller_creates_product_successfully_${CASE_SUFFIX}.status"
cleanup_files() {
  rm -f "$REGISTER_RESPONSE" "$RESPONSE_FILE" "$STATUS_FILE"
}
trap cleanup_files EXIT

# Given
curl -sS -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"Password123!\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\",\"bio\":\"Beautiful handmade ceramics\"}" \
  > "$REGISTER_RESPONSE"
TOKEN="$(jq -r '.token' "$REGISTER_RESPONSE")"
USER_ID="$(jq -r '.user.id' "$REGISTER_RESPONSE")"
SELLER_ID="$(jq -r '.user.sellerProfile.id' "$REGISTER_RESPONSE")"
[ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]
[ -n "$USER_ID" ] && [ "$USER_ID" != "null" ]
[ -n "$SELLER_ID" ] && [ "$SELLER_ID" != "null" ]
psql "$DATABASE_URL" -c "UPDATE \"User\" SET status = 'ACTIVE' WHERE id = '${USER_ID}';" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  -d "{\"title\":\"${PRODUCT_TITLE}\",\"description\":\"Beautiful blue glazed vase\",\"category\":\"HOME_DECOR\",\"price_cents\":4500,\"stock_qty\":10,\"photos\":[\"https://example.com/photo1.jpg\"]}" \
  > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "201" ]
jq -e --arg seller_id "$SELLER_ID" --arg title "$PRODUCT_TITLE" '.sellerId == $seller_id and .title == $title and .status == "ACTIVE" and .visible == true and (.id | length > 0)' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:approved_seller_creates_product_successfully"

# Cleanup
PRODUCT_ID="$(jq -r '.id' "$RESPONSE_FILE")"
if [ -n "$PRODUCT_ID" ] && [ "$PRODUCT_ID" != "null" ]; then
  psql "$DATABASE_URL" -c "DELETE FROM \"Product\" WHERE id = '${PRODUCT_ID}';" >/dev/null
fi
psql "$DATABASE_URL" -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" = '${USER_ID}';" >/dev/null
psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE id = '${USER_ID}';" >/dev/null
