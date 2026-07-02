#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="seller_without_profile_not_found"
USER_ID="user_${TEST_ID}_${CASE_SUFFIX}"
USER_EMAIL="${TEST_ID}-${CASE_SUFFIX}@example.com"
TOKEN_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.token"
RESPONSE_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.status"
cleanup_files() {
  rm -f "$TOKEN_FILE" "$RESPONSE_FILE" "$STATUS_FILE"
}
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('${USER_ID}', '${USER_EMAIL}', 'hash', 'SELLER', 'ACTIVE');" >/dev/null
node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"SELLER",status:"ACTIVE"}, process.env.JWT_SECRET));' "$USER_ID" "$USER_EMAIL" > "$TOKEN_FILE"
TOKEN="$(cat "$TOKEN_FILE")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X GET "$BASE_URL/seller/dashboard" \
  -H "Authorization: Bearer ${TOKEN}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "404" ]
grep -F '"error":"Seller profile not found"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:seller_without_profile_not_found"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
