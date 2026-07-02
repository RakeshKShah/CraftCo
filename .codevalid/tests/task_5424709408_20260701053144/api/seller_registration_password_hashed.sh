#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="seller-hash-${CASE_SUFFIX}@test.com"
PASSWORD='PlainPassword123'
RESPONSE_FILE="/tmp/seller_registration_password_hashed_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/seller_registration_password_hashed_${CASE_SUFFIX}.status"
HASH_FILE="/tmp/seller_registration_password_hashed_db_${CASE_SUFFIX}.txt"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE" "$HASH_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email = '${SELLER_EMAIL}');" >/dev/null
psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE email = '${SELLER_EMAIL}';" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"Secure Shop\"}" > "$STATUS_FILE"
psql "$DATABASE_URL" -t -A -c "SELECT \"passwordHash\" FROM \"User\" WHERE email = '${SELLER_EMAIL}';" > "$HASH_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
PASSWORD_HASH="$(tr -d '\r\n' < "$HASH_FILE")"
[ "$STATUS" = "201" ]
[ -n "$PASSWORD_HASH" ]
printf '%s' "$PASSWORD_HASH" | grep -E '^\$2[aby]\$' >/dev/null
[ "$PASSWORD_HASH" != "$PASSWORD" ]
if printf '%s' "$PASSWORD_HASH" | grep -F "$PASSWORD" >/dev/null; then
  exit 1
fi

echo "CODEVALID_TEST_ASSERTION_OK:seller_registration_password_hashed"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email = '${SELLER_EMAIL}');" >/dev/null
psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE email = '${SELLER_EMAIL}';" >/dev/null
