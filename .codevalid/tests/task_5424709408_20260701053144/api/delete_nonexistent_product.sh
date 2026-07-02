#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="delete_nonexistent_product"
USER_EMAIL="seller-${TEST_ID}-${CASE_SUFFIX}@example.com"
USER_PASSWORD="Password123!"
PRODUCT_ID="prod-nonexistent-${CASE_SUFFIX}"
REGISTER_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}_register.json"
RESPONSE_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$REGISTER_FILE" "$RESPONSE_FILE" "$STATUS_FILE"; }
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '${PRODUCT_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE email = '${USER_EMAIL}';" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
curl -sS -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"${USER_EMAIL}\",\"password\":\"${USER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"Active Store ${CASE_SUFFIX}\",\"bio\":\"nonexistent delete test\"}" \
  > "$REGISTER_FILE"
TOKEN="$(jq -r '.token' "$REGISTER_FILE")"
USER_ID="$(jq -r '.user.id' "$REGISTER_FILE")"
[ "$TOKEN" != "null" ]
psql "$DATABASE_URL" -c "UPDATE users SET status = 'ACTIVE' WHERE id = '${USER_ID}';" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X DELETE \
  "$BASE_URL/products/${PRODUCT_ID}" \
  -H "Authorization: Bearer ${TOKEN}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "404" ]
grep -F '"error":"Product not found"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:delete_nonexistent_product"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM users WHERE email = '${USER_EMAIL}';" >/dev/null 2>&1 || true
