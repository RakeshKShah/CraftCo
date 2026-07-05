#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="invalid-product-${CASE_SUFFIX}@example.com"
REGISTER_RESPONSE="/tmp/invalid_product_data_returns_validation_error_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/invalid_product_data_returns_validation_error_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/invalid_product_data_returns_validation_error_${CASE_SUFFIX}.status"
cleanup_files() {
  rm -f "$REGISTER_RESPONSE" "$RESPONSE_FILE" "$STATUS_FILE"
}
trap cleanup_files EXIT

# Given
curl -sS -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"Password123!\",\"role\":\"SELLER\",\"storeName\":\"Valid Seller ${CASE_SUFFIX}\",\"bio\":\"Ready to sell\"}" \
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
  -d '{"title":"","description":"Test","category":"INVALID","price_cents":-100,"stock_qty":-5,"photos":[]}' \
  > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "400" ]
jq -e 'has("error") and (.error | type == "string") and (.error | length > 0)' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:invalid_product_data_returns_validation_error"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" = '${USER_ID}';" >/dev/null
psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE id = '${USER_ID}';" >/dev/null
