#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="database_error_returns_500"
ADMIN_ID="admin-${TEST_ID}-${CASE_SUFFIX}"
ADMIN_EMAIL="${ADMIN_ID}@example.com"
ADMIN_PASSWORD='AdminPass123!'
SELLER_USER_ID="seller-user-${TEST_ID}-${CASE_SUFFIX}"
SELLER_ID="seller-dberror-${CASE_SUFFIX}"
LOGIN_JSON="/tmp/${TEST_ID}_login_${CASE_SUFFIX}.json"
RESPONSE_JSON="/tmp/${TEST_ID}_response_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/${TEST_ID}_status_${CASE_SUFFIX}.txt"
cleanup() {
  curl -sS -X DELETE "http://toxiproxy:8474/proxies/postgres/toxics/cut_write_${CASE_SUFFIX}" >/dev/null 2>&1 || true
  rm -f "$LOGIN_JSON" "$RESPONSE_JSON" "$STATUS_FILE"
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id IN ('${SELLER_USER_ID}','${ADMIN_ID}');" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Given — seed an admin and active seller, then inject a postgres timeout toxic through toxiproxy
HASH='$2b$10$DOWSDR9Kt5I9zQJmlp7iUuY8j5B5P6M8JrIoYNewc19hXtOD87o5e'
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${ADMIN_ID}', '${ADMIN_EMAIL}', '${HASH}', 'ADMIN', 'ACTIVE', NOW());
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', 'seller-${TEST_ID}-${CASE_SUFFIX}@example.com', '${HASH}', 'SELLER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_ID}', '${SELLER_USER_ID}', 'DB Error Store ${CASE_SUFFIX}', 'Failure path');
SQL
curl -sS -o "$LOGIN_JSON" -w '%{http_code}' \
  -X POST "$BASE_URL/auth/login" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\"}" > "$STATUS_FILE"
[ "$(cat "$STATUS_FILE")" = "200" ]
ADMIN_TOKEN="$(jq -r '.token' "$LOGIN_JSON")"
[ "$ADMIN_TOKEN" != "null" ]
curl -sS -X POST "http://toxiproxy:8474/proxies/postgres/toxics" \
  -H 'Content-Type: application/json' \
  --data "{\"name\":\"cut_write_${CASE_SUFFIX}\",\"type\":\"timeout\",\"stream\":\"downstream\",\"attributes\":{\"timeout\":1000}}" >/dev/null

# When — admin attempts to update seller status while database writes fail
curl -sS -o "$RESPONSE_JSON" -w '%{http_code}' \
  -X PUT "$BASE_URL/admin/sellers/${SELLER_ID}" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  --data '{"status":"SUSPENDED"}' > "$STATUS_FILE"

# Then — endpoint returns 500 Update failed and seller status remains unchanged
[ "$(cat "$STATUS_FILE")" = "500" ]
jq -e '.error == "Update failed"' "$RESPONSE_JSON" >/dev/null
curl -sS -X DELETE "http://toxiproxy:8474/proxies/postgres/toxics/cut_write_${CASE_SUFFIX}" >/dev/null
[ "$(psql "$DATABASE_URL" -t -A -c "SELECT status FROM users WHERE id='${SELLER_USER_ID}';")" = "ACTIVE" ]

echo "CODEVALID_TEST_ASSERTION_OK:database_error_returns_500"

# Cleanup — remove toxic, seller, and admin
