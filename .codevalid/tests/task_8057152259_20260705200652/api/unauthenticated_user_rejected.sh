#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="unauthenticated_user_rejected"
BUYER_ID="buyer_unauth_${CASE_SUFFIX}"
BUYER_EMAIL="buyer-unauth-${CASE_SUFFIX}@example.com"
ORDER_ID="order_unauth_${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.status"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM orders WHERE id = '${ORDER_ID}';" >/dev/null
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '${BUYER_ID}';" >/dev/null
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('${BUYER_ID}', '${BUYER_EMAIL}', 'not-used', 'BUYER', 'ACTIVE');" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO orders (id, buyer_id, status, total_cents, platform_fee_cents) VALUES ('${ORDER_ID}', '${BUYER_ID}', 'SHIPPED', 1900, 190);" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST \
  "$BASE_URL/orders/${ORDER_ID}/deliver" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "401" ]
grep -Ei 'auth|unauth|token|login' "$RESPONSE_FILE" >/dev/null
DB_STATUS="$(psql "$DATABASE_URL" -t -A -c "SELECT status FROM orders WHERE id = '${ORDER_ID}';")"
[ "$DB_STATUS" = "SHIPPED" ]
echo "CODEVALID_TEST_ASSERTION_OK:unauthenticated_user_rejected"

# Cleanup
:
