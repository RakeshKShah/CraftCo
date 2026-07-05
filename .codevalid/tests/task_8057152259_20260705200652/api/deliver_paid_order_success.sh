#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="deliver_paid_order_success"
BUYER_EMAIL="buyer-paid-${CASE_SUFFIX}@example.com"
BUYER_PASSWORD="Password123!"
BUYER_ID="buyer_paid_${CASE_SUFFIX}"
ORDER_ID="order_paid_${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.status"
LOGIN_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.login.json"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE" "$LOGIN_FILE"
}
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM orders WHERE id = '${ORDER_ID}';" >/dev/null
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '${BUYER_ID}';" >/dev/null
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
HASHED_PASSWORD="$(node -e "console.log(require('bcryptjs').hashSync(process.argv[1], 10))" "$BUYER_PASSWORD")"
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('${BUYER_ID}', '${BUYER_EMAIL}', '${HASHED_PASSWORD}', 'BUYER', 'ACTIVE');" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO orders (id, buyer_id, status, total_cents, platform_fee_cents) VALUES ('${ORDER_ID}', '${BUYER_ID}', 'PAID', 4100, 410);" >/dev/null
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
[ "$STATUS" = "200" ]
grep -F '"success":true' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"DELIVERED"' "$RESPONSE_FILE" >/dev/null
DB_STATUS="$(psql "$DATABASE_URL" -t -A -c "SELECT status FROM orders WHERE id = '${ORDER_ID}';")"
[ "$DB_STATUS" = "DELIVERED" ]
echo "CODEVALID_TEST_ASSERTION_OK:deliver_paid_order_success"

# Cleanup
:
