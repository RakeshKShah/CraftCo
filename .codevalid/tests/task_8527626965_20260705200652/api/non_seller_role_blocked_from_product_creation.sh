#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="buyer-${CASE_SUFFIX}@example.com"
REGISTER_RESPONSE="/tmp/non_seller_role_blocked_from_product_creation_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/non_seller_role_blocked_from_product_creation_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/non_seller_role_blocked_from_product_creation_${CASE_SUFFIX}.status"
cleanup_files() {
  rm -f "$REGISTER_RESPONSE" "$RESPONSE_FILE" "$STATUS_FILE"
}
trap cleanup_files EXIT

# Given
curl -sS -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"Password123!\",\"role\":\"BUYER\"}" \
  > "$REGISTER_RESPONSE"
TOKEN="$(jq -r '.token' "$REGISTER_RESPONSE")"
USER_ID="$(jq -r '.user.id' "$REGISTER_RESPONSE")"
[ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  -d "{\"title\":\"Buyer Product ${CASE_SUFFIX}\",\"description\":\"Unauthorized\",\"category\":\"HOME_DECOR\",\"price_cents\":4500,\"stock_qty\":10,\"photos\":[\"https://example.com/photo1.jpg\"]}" \
  > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "403" ]
jq -e '.error == "Seller access required"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:non_seller_role_blocked_from_product_creation"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE id = '${USER_ID}';" >/dev/null
