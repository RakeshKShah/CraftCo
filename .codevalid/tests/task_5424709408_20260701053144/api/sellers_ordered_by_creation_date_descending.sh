#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="sellers_ordered_by_creation_date_descending"
TMP_DIR="$(mktemp -d)"
RESPONSE_FILE="$TMP_DIR/response.json"
LOGIN_FILE="$TMP_DIR/login.json"
ADMIN_EMAIL="${TEST_ID}.admin.${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD='AdminPass123!'

cleanup_db() {
  psql "$DATABASE_URL" <<SQL >/dev/null 2>&1 || true
DELETE FROM seller_profiles WHERE id IN ('seller-old-${CASE_SUFFIX}','seller-middle-${CASE_SUFFIX}','seller-new-${CASE_SUFFIX}');
DELETE FROM users WHERE id IN ('admin-003-${CASE_SUFFIX}','user-old-${CASE_SUFFIX}','user-middle-${CASE_SUFFIX}','user-new-${CASE_SUFFIX}');
SQL
  rm -rf "$TMP_DIR"
}
trap cleanup_db EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES
  ('admin-003-${CASE_SUFFIX}', '${ADMIN_EMAIL}', '\$2b\$10\$D0hUPmZl7Q3kN6lJzi10Suq5mN0eZZF9RnBbTK1ZBOqVaki3P6KyK', 'ADMIN', 'ACTIVE', '2024-01-01T00:00:00Z'),
  ('user-old-${CASE_SUFFIX}', 'old.${CASE_SUFFIX}@store.com', 'seed', 'SELLER', 'ACTIVE', '2023-01-15T10:00:00Z'),
  ('user-middle-${CASE_SUFFIX}', 'middle.${CASE_SUFFIX}@store.com', 'seed', 'SELLER', 'ACTIVE', '2023-06-10T09:15:00Z'),
  ('user-new-${CASE_SUFFIX}', 'new.${CASE_SUFFIX}@store.com', 'seed', 'SELLER', 'PENDING', '2024-01-20T14:30:00Z');
INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES
  ('seller-old-${CASE_SUFFIX}', 'user-old-${CASE_SUFFIX}', 'Old Store', 'Old bio'),
  ('seller-middle-${CASE_SUFFIX}', 'user-middle-${CASE_SUFFIX}', 'Middle Store', 'Middle bio'),
  ('seller-new-${CASE_SUFFIX}', 'user-new-${CASE_SUFFIX}', 'New Store', 'New bio');
SQL
curl -sS -o "$LOGIN_FILE" -X POST "$BASE_URL/auth/login" \n  -H 'Content-Type: application/json' \n  --data "{"email":"$ADMIN_EMAIL","password":"AdminPass123!"}"
ADMIN_TOKEN="$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$LOGIN_FILE")"
[ -n "$ADMIN_TOKEN" ]

# When
HTTP_CODE="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/admin/sellers" -H "Authorization: Bearer $ADMIN_TOKEN")"
BODY_COMPACT="$(tr -d '\n' < "$RESPONSE_FILE")"

# Then
[ "$HTTP_CODE" = "200" ]
printf '%s' "$BODY_COMPACT" | grep -E "seller-new-${CASE_SUFFIX}.*seller-middle-${CASE_SUFFIX}.*seller-old-${CASE_SUFFIX}" >/dev/null
COUNT="$(grep -o '"id":"seller-[^"]*' "$RESPONSE_FILE" | wc -l | tr -d ' ')"
[ "$COUNT" = "3" ]
echo 'CODEVALID_TEST_ASSERTION_OK:sellers_ordered_by_creation_date_descending'

# Cleanup
cleanup_db
trap - EXIT
