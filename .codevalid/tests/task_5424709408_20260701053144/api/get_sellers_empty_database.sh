#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="get_sellers_empty_database"
TMP_DIR="$(mktemp -d)"
RESPONSE_FILE="$TMP_DIR/response.json"
LOGIN_FILE="$TMP_DIR/login.json"
ADMIN_ID="admin-${CASE_SUFFIX}"
ADMIN_EMAIL="${TEST_ID}.admin.${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD='AdminPass123!'
PASSWORD_HASH='\$2b\$10\$D0hUPmZl7Q3kN6lJzi10Suq5mN0eZZF9RnBbTK1ZBOqVaki3P6KyK'

cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id = '${ADMIN_ID}';" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup_db EXIT

# Given — create only an admin user and ensure this test adds no seller profiles
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${ADMIN_ID}', '${ADMIN_EMAIL}', '${PASSWORD_HASH}', 'ADMIN', 'ACTIVE', '2024-06-11T00:00:00Z');
SQL

curl -sS -o "$LOGIN_FILE" -X POST "$BASE_URL/auth/login" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\"}"
ADMIN_TOKEN="$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$LOGIN_FILE")"
[ -n "$ADMIN_TOKEN" ]

# When — fetch the admin seller list from an empty seller-profile dataset for this test
HTTP_CODE="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/admin/sellers" \
  -H "Authorization: Bearer $ADMIN_TOKEN")"
BODY="$(tr -d '\n[:space:]' < "$RESPONSE_FILE")"

# Then — assert HTTP 200 and empty JSON array
[ "$HTTP_CODE" = "200" ]
[ "$BODY" = "[]" ]
echo 'CODEVALID_TEST_ASSERTION_OK:get_sellers_empty_database'

# Cleanup — delete the seeded admin user and temp files
cleanup_db
trap - EXIT
