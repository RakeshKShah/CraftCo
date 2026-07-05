#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="order_not_found_returns_404"
BUYER_ID="buyer_missing_${CASE_SUFFIX}"
BUYER_EMAIL="buyer-missing-${CASE_SUFFIX}@example.com"
BUYER_PASSWORD="Password123!"
ORDER_ID="missing_order_${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.status"
LOGIN_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.login.json"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE" "$LOGIN_FILE"
}
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '${BUYER_ID}';" >/dev/null
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
HASHED_PASSWORD="$(node -e "console.log(require('bcryptjs').hashSync(process.argv[1], 10))" "$BUYER_PASSWORD")"
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('${BUYER_ID}', '${BUYER_EMAIL}', '${HASHED_PASSWORD}', 'BUYER', 'ACTIVE');" >/dev/null
curl -sS -o "$LOGIN_FILE" -w '%{http_code}' -X POST "$BASE_URL/auth/login" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${BUYER_EMAIL}\",\"password\":\"${BUYER_PASSWORD}\"}" > "$STATUS_FILE"
LOGIN_STATUS="$(cat "$STATUS_FILE")"
[ "$LOGIN_STATUS" = "200" ]
TOKEN="$(node -e "const fs=require('fs'); const data=JSON.parse(fs.readFileSync(process.argv[1],'utf8')); process.stdout.write(data.token);" "$LOGIN_FILE")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST \
  "$BASE_URL/orders/${ORDER_ID}/deliver" \
  -H "Authorization: Bearer ${TOKEN}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "404" ]
grep -F '"error":"Order not found"' "$RESPONSE_FILE" >/dev/null
echo "CODEVALID_TEST_ASSERTION_OK:order_not_found_returns_404"

# Cleanup
:
