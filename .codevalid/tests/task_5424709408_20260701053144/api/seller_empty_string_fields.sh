#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="seller-empty-${CASE_SUFFIX}@test.com"
RESPONSE_FILE="/tmp/seller_empty_string_fields_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/seller_empty_string_fields_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email = '${SELLER_EMAIL}');" >/dev/null
psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE email = '${SELLER_EMAIL}';" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"SecurePass123!\",\"role\":\"SELLER\",\"storeName\":\"\",\"bio\":\"\"}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "201" ]
grep -F '"storeName":""' "$RESPONSE_FILE" >/dev/null
grep -F '"bio":""' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:seller_empty_string_fields"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email = '${SELLER_EMAIL}');" >/dev/null
psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE email = '${SELLER_EMAIL}';" >/dev/null
