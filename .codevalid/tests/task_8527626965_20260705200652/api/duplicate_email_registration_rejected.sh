#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="existing-${CASE_SUFFIX}@example.com"
FIRST_PASSWORD='OriginalPass123!'
SECOND_PASSWORD='AnotherPass456!'
TMP_DIR="$(mktemp -d)"
FIRST_RESPONSE="$TMP_DIR/first.json"
FIRST_STATUS="$TMP_DIR/first.status"
SECOND_RESPONSE="$TMP_DIR/second.json"
SECOND_STATUS="$TMP_DIR/second.status"
cleanup() {
  USER_ID="$(jq -r '.user.id // empty' "$FIRST_RESPONSE" 2>/dev/null || true)"
  SELLER_ID="$(jq -r '.user.sellerProfile.id // empty' "$FIRST_RESPONSE" 2>/dev/null || true)"
  [ -n "$SELLER_ID" ] && psql "$DATABASE_URL" -c "DELETE FROM \"SellerProfile\" WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
  [ -n "$USER_ID" ] && psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email='${EMAIL}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE email='${EMAIL}';" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Given
psql "$DATABASE_URL" -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email='${EMAIL}');" >/dev/null
psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE email='${EMAIL}';" >/dev/null
curl -sS -o "$FIRST_RESPONSE" -w '%{http_code}' -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"${FIRST_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"Original Shop ${CASE_SUFFIX}\"}" > "$FIRST_STATUS"
[ "$(cat "$FIRST_STATUS")" = "201" ]

# When
curl -sS -o "$SECOND_RESPONSE" -w '%{http_code}' -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"${SECOND_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"Duplicate Shop ${CASE_SUFFIX}\"}" > "$SECOND_STATUS"

# Then
[ "$(cat "$SECOND_STATUS")" = "400" ]
jq -e '.error == "Email already registered"' "$SECOND_RESPONSE" >/dev/null
USER_COUNT="$(psql "$DATABASE_URL" -At -c "SELECT COUNT(*) FROM \"User\" WHERE email='${EMAIL}';")"
[ "$USER_COUNT" = "1" ]
echo "CODEVALID_TEST_ASSERTION_OK:duplicate_email_registration_rejected"

# Cleanup
# handled by trap
