#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="seller-defaults-${CASE_SUFFIX}@test.com"
RESPONSE_FILE="/tmp/seller_registration_with_default_values_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/seller_registration_with_default_values_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email = '${SELLER_EMAIL}');" >/dev/null
psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE email = '${SELLER_EMAIL}';" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"SecurePass123!\",\"role\":\"SELLER\"}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "201" ]
grep -F '"role":"SELLER"' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"PENDING"' "$RESPONSE_FILE" >/dev/null
grep -F '"storeName":"My Shop"' "$RESPONSE_FILE" >/dev/null
grep -F '"bio":""' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:seller_registration_with_default_values"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email = '${SELLER_EMAIL}');" >/dev/null
psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE email = '${SELLER_EMAIL}';" >/dev/null
