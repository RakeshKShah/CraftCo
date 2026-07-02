#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EXISTING_EMAIL="existing-user-${CASE_SUFFIX}@test.com"
RESPONSE_FILE="/tmp/duplicate_email_registration_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/duplicate_email_registration_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE email = '${EXISTING_EMAIL}';" >/dev/null
FIRST_STATUS="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EXISTING_EMAIL}\",\"password\":\"SecurePass123!\",\"role\":\"BUYER\"}")"
[ "$FIRST_STATUS" = "201" ]

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EXISTING_EMAIL}\",\"password\":\"SecurePass123!\",\"role\":\"BUYER\"}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "400" ]
grep -F '"error":"Email already registered"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:duplicate_email_registration"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE email = '${EXISTING_EMAIL}';" >/dev/null
