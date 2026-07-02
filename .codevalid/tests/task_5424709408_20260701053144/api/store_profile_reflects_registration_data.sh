#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="store_profile_reflects_registration_data"
USER_EMAIL="${TEST_ID}-${CASE_SUFFIX}@example.com"
USER_PASSWORD="Password123!"
REGISTER_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}_register.json"
RESPONSE_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.status"
cleanup_files() {
  rm -f "$REGISTER_FILE" "$RESPONSE_FILE" "$STATUS_FILE"
}
cleanup_db() {
  if [ "${USER_ID:-}" != "" ]; then
    psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE user_id='${USER_ID}';" >/dev/null 2>&1 || true
    psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
  else
    psql "$DATABASE_URL" -c "DELETE FROM users WHERE email='${USER_EMAIL}';" >/dev/null 2>&1 || true
  fi
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
curl -sS -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"${USER_EMAIL}\",\"password\":\"${USER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"Handmade Crafts\",\"bio\":\"Artisan jewelry and decor\"}" \
  > "$REGISTER_FILE"
TOKEN="$(jq -r '.token' "$REGISTER_FILE")"
USER_ID="$(jq -r '.user.id' "$REGISTER_FILE")"
[ "$TOKEN" != "null" ]
[ "$USER_ID" != "null" ]
psql "$DATABASE_URL" -c "UPDATE users SET status='ACTIVE' WHERE id='${USER_ID}';" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X GET "$BASE_URL/seller/dashboard" \
  -H "Authorization: Bearer ${TOKEN}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
grep -F '"store_name":"Handmade Crafts"' "$RESPONSE_FILE" >/dev/null
grep -F '"bio":"Artisan jewelry and decor"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:store_profile_reflects_registration_data"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE user_id='${USER_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
