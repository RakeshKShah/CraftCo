#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="invalid_status_value"
ADMIN_ID="admin-${TEST_ID}-${CASE_SUFFIX}"
ADMIN_EMAIL="${ADMIN_ID}@example.com"
ADMIN_PASSWORD='AdminPass123!'
SELLER_USER_ID="seller-user-${TEST_ID}-${CASE_SUFFIX}"
SELLER_ID="seller-${TEST_ID}-${CASE_SUFFIX}"
LOGIN_JSON="/tmp/${TEST_ID}_login_${CASE_SUFFIX}.json"
UPDATE_JSON="/tmp/${TEST_ID}_update_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/${TEST_ID}_status_${CASE_SUFFIX}.txt"
cleanup() {
  rm -f "$LOGIN_JSON" "$UPDATE_JSON" "$STATUS_FILE"
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id IN ('${SELLER_USER_ID}','${ADMIN_ID}');" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Given — seed an admin and an existing seller whose status should remain unchanged on invalid input
ADMIN_HASH='$2b$10$DOWSDR9Kt5I9zQJmlp7iUuY8j5B5P6M8JrIoYNewc19hXtOD87o5e'
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${ADMIN_ID}', '${ADMIN_EMAIL}', '${ADMIN_HASH}', 'ADMIN', 'ACTIVE', NOW());
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', 'seller-${TEST_ID}-${CASE_SUFFIX}@example.com', '${ADMIN_HASH}', 'SELLER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_ID}', '${SELLER_USER_ID}', 'Invalid Status Store ${CASE_SUFFIX}', 'Validation test bio');
SQL
curl -sS -o "$LOGIN_JSON" -w '%{http_code}' \
  -X POST "$BASE_URL/auth/login" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\"}" > "$STATUS_FILE"
[ "$(cat "$STATUS_FILE")" = "200" ]
ADMIN_TOKEN="$(jq -r '.token' "$LOGIN_JSON")"
[ "$ADMIN_TOKEN" != "null" ]
BEFORE_STATUS="$(psql "$DATABASE_URL" -t -A -c "SELECT status FROM users WHERE id='${SELLER_USER_ID}';")"
[ "$BEFORE_STATUS" = "ACTIVE" ]

# When — send an invalid seller status value to the admin update API
curl -sS -o "$UPDATE_JSON" -w '%{http_code}' \
  -X PUT "$BASE_URL/admin/sellers/${SELLER_ID}" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  --data '{"status":"INVALID_STATUS"}' > "$STATUS_FILE"

# Then — API returns 400 with validation error and seller status remains unchanged
[ "$(cat "$STATUS_FILE")" = "400" ]
jq -e '.error | length > 0' "$UPDATE_JSON" >/dev/null
grep -E 'Invalid option|expected|status' "$UPDATE_JSON" >/dev/null
[ "$(psql "$DATABASE_URL" -t -A -c "SELECT status FROM users WHERE id='${SELLER_USER_ID}';")" = "ACTIVE" ]

echo "CODEVALID_TEST_ASSERTION_OK:invalid_status_value"

# Cleanup — remove seeded seller profile and users
