#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="database_update_failure"
ADMIN_ID="admin-${TEST_ID}-${CASE_SUFFIX}"
ADMIN_EMAIL="${ADMIN_ID}@example.com"
ADMIN_PASSWORD='AdminPass123!'
SELLER_USER_ID="seller-user-${TEST_ID}-${CASE_SUFFIX}"
SELLER_ID="seller-${TEST_ID}-${CASE_SUFFIX}"
LOGIN_JSON="/tmp/${TEST_ID}_login_${CASE_SUFFIX}.json"
UPDATE_JSON="/tmp/${TEST_ID}_update_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/${TEST_ID}_status_${CASE_SUFFIX}.txt"
TOXIC_JSON="/tmp/${TEST_ID}_toxic_${CASE_SUFFIX}.json"
cleanup() {
  curl -sS -X DELETE "http://toxiproxy:8474/proxies/postgres/toxics/${TEST_ID}_cut" >/dev/null 2>&1 || true
  rm -f "$LOGIN_JSON" "$UPDATE_JSON" "$STATUS_FILE" "$TOXIC_JSON"
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id IN ('${SELLER_USER_ID}','${ADMIN_ID}');" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Given — seed an admin and seller, then prepare a toxiproxy failure on the postgres proxy
ADMIN_HASH='$2b$10$DOWSDR9Kt5I9zQJmlp7iUuY8j5B5P6M8JrIoYNewc19hXtOD87o5e'
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${ADMIN_ID}', '${ADMIN_EMAIL}', '${ADMIN_HASH}', 'ADMIN', 'ACTIVE', NOW());
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', 'seller-${TEST_ID}-${CASE_SUFFIX}@example.com', '${ADMIN_HASH}', 'SELLER', 'PENDING', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_ID}', '${SELLER_USER_ID}', 'DB Failure Store ${CASE_SUFFIX}', 'DB failure test bio');
SQL
curl -sS -o "$LOGIN_JSON" -w '%{http_code}' \
  -X POST "$BASE_URL/auth/login" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\"}" > "$STATUS_FILE"
[ "$(cat "$STATUS_FILE")" = "200" ]
ADMIN_TOKEN="$(jq -r '.token' "$LOGIN_JSON")"
[ "$ADMIN_TOKEN" != "null" ]
curl -sS -o "$TOXIC_JSON" -w '%{http_code}' \
  -X POST "http://toxiproxy:8474/proxies/postgres/toxics" \
  -H 'Content-Type: application/json' \
  --data "{\"name\":\"${TEST_ID}_cut\",\"type\":\"timeout\",\"stream\":\"downstream\",\"attributes\":{\"timeout\":15000}}" > "$STATUS_FILE"
[ "$(cat "$STATUS_FILE")" = "200" ]

# When — call the admin seller update while database traffic is failing through toxiproxy
curl -sS -o "$UPDATE_JSON" -w '%{http_code}' \
  -X PUT "$BASE_URL/admin/sellers/${SELLER_ID}" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  --data '{"status":"ACTIVE"}' > "$STATUS_FILE" || true

# Then — API returns 500 Update failed and seller status stays unchanged
[ "$(cat "$STATUS_FILE")" = "500" ]
jq -e '.error == "Update failed"' "$UPDATE_JSON" >/dev/null
curl -sS -X DELETE "http://toxiproxy:8474/proxies/postgres/toxics/${TEST_ID}_cut" >/dev/null
[ "$(psql "$DATABASE_URL" -t -A -c "SELECT status FROM users WHERE id='${SELLER_USER_ID}';")" = "PENDING" ]

echo "CODEVALID_TEST_ASSERTION_OK:database_update_failure"

# Cleanup — remove toxic and seeded seller/admin records
