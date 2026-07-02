#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="get_sellers_fields_presence"
TMP_DIR="$(mktemp -d)"
RESPONSE_FILE="$TMP_DIR/response.json"
LOGIN_FILE="$TMP_DIR/login.json"
ADMIN_ID="admin-${CASE_SUFFIX}"
ADMIN_EMAIL="${TEST_ID}.admin.${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD='AdminPass123!'
SELLER_USER_ID="u5-${CASE_SUFFIX}"
SELLER_PROFILE_ID="sp5-${CASE_SUFFIX}"
PASSWORD_HASH='\$2b\$10\$D0hUPmZl7Q3kN6lJzi10Suq5mN0eZZF9RnBbTK1ZBOqVaki3P6KyK'

cleanup_db() {
  psql "$DATABASE_URL" <<SQL >/dev/null 2>&1 || true
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id IN ('${SELLER_USER_ID}','${ADMIN_ID}');
SQL
  rm -rf "$TMP_DIR"
}
trap cleanup_db EXIT

# Given — seed one pending seller with store name and bio plus an admin account for authenticated access
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES
  ('${ADMIN_ID}', '${ADMIN_EMAIL}', '${PASSWORD_HASH}', 'ADMIN', 'ACTIVE', '2024-06-14T00:00:00Z'),
  ('${SELLER_USER_ID}', 'seller5.${CASE_SUFFIX}@example.com', '${PASSWORD_HASH}', 'SELLER', 'PENDING', '2024-01-06T06:00:00Z');

INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'New Store', 'Fresh bio');
SQL

curl -sS -o "$LOGIN_FILE" -X POST "$BASE_URL/auth/login" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\"}"
ADMIN_TOKEN="$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$LOGIN_FILE")"
[ -n "$ADMIN_TOKEN" ]

# When — request the admin seller list
HTTP_CODE="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/admin/sellers" \
  -H "Authorization: Bearer $ADMIN_TOKEN")"
BODY_MIN="$(tr -d '\n' < "$RESPONSE_FILE")"

# Then — assert the response includes all required seller-management fields with populated values
[ "$HTTP_CODE" = "200" ]
printf '%s' "$BODY_MIN" | grep -F '"id":"' >/dev/null
printf '%s' "$BODY_MIN" | grep -F '"user_id":"' >/dev/null
printf '%s' "$BODY_MIN" | grep -F '"email":"seller5.' >/dev/null
printf '%s' "$BODY_MIN" | grep -F '"store_name":"New Store"' >/dev/null
printf '%s' "$BODY_MIN" | grep -F '"bio":"Fresh bio"' >/dev/null
printf '%s' "$BODY_MIN" | grep -F '"status":"PENDING"' >/dev/null
printf '%s' "$BODY_MIN" | grep -F '"product_count":0' >/dev/null
printf '%s' "$BODY_MIN" | grep -F '"created_at":"2024-01-06T06:00:00.000Z"' >/dev/null
echo 'CODEVALID_TEST_ASSERTION_OK:get_sellers_fields_presence'

# Cleanup — remove seeded profile, users, and temp files
cleanup_db
trap - EXIT
