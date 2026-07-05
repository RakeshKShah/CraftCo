#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="non_buyer_non_admin_forbidden"
BUYER_ID="buyer_owner_${CASE_SUFFIX}"
BUYER_EMAIL="buyer-owner-${CASE_SUFFIX}@example.com"
OTHER_ID="buyer_other_${CASE_SUFFIX}"
OTHER_EMAIL="buyer-other-${CASE_SUFFIX}@example.com"
OTHER_PASSWORD="Password123!"
ORDER_ID="order_forbidden_${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.status"
LOGIN_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.login.json"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE" "$LOGIN_FILE"
}
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM orders WHERE id = '${ORDER_ID}';" >/dev/null
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id IN ('${OTHER_ID}', '${BUYER_ID}');" >/dev/null
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
OTHER_HASHED_PASSWORD="$(node -e "console.log(require('bcryptjs').hashSync(process.argv[1], 10))" "$OTHER_PASSWORD")"
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('${BUYER_ID}', '${BUYER_EMAIL}', 'not-used', 'BUYER', 'ACTIVE');" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('${OTHER_ID}', '${OTHER_EMAIL}', '${OTHER_HASHED_PASSWORD}', 'BUYER', 'ACTIVE');" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO orders (id, buyer_id, status, total_cents, platform_fee_cents) VALUES ('${ORDER_ID}', '${BUYER_ID}', 'SHIPPED', 3400, 340);" >/dev/null
curl -sS -o "$LOGIN_FILE" -w '%{http_code}' -X POST "$BASE_URL/auth/login" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${OTHER_EMAIL}\",\"password\":\"${OTHER_PASSWORD}\"}" > "$STATUS_FILE"
LOGIN_STATUS="$(cat "$STATUS_FILE")"
[ "$LOGIN_STATUS" = "200" ]
TOKEN="$(node -e "const fs=require('fs'); const data=JSON.parse(fs.readFileSync(process.argv[1],'utf8')); process.stdout.write(data.token);" "$LOGIN_FILE")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST \
  "$BASE_URL/orders/${ORDER_ID}/deliver" \
  -H "Authorization: Bearer ${TOKEN}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "403" ]
grep -F 'Only the buyer or admin can confirm delivery' "$RESPONSE_FILE" >/dev/null
DB_STATUS="$(psql "$DATABASE_URL" -t -A -c "SELECT status FROM orders WHERE id = '${ORDER_ID}';")"
[ "$DB_STATUS" = "SHIPPED" ]
echo "CODEVALID_TEST_ASSERTION_OK:non_buyer_non_admin_forbidden"

# Cleanup
:
