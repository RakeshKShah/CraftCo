#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="unauthorized_access_rejected"
TMP_DIR="$(mktemp -d)"
RESPONSE_FILE="$TMP_DIR/response.json"
LOGIN_FILE="$TMP_DIR/login.json"
USER_EMAIL="regular.${CASE_SUFFIX}@user.com"
USER_PASSWORD='AdminPass123!'

cleanup_db() {
  psql "$DATABASE_URL" <<SQL >/dev/null 2>&1 || true
DELETE FROM seller_profiles WHERE id = 'seller-existing-001-${CASE_SUFFIX}';
DELETE FROM users WHERE id IN ('user-reg-001-${CASE_SUFFIX}','seller-user-existing-001-${CASE_SUFFIX}');
SQL
  rm -rf "$TMP_DIR"
}
trap cleanup_db EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES
  ('user-reg-001-${CASE_SUFFIX}', '${USER_EMAIL}', '\$2b\$10\$D0hUPmZl7Q3kN6lJzi10Suq5mN0eZZF9RnBbTK1ZBOqVaki3P6KyK', 'BUYER', 'ACTIVE', '2024-06-02T00:00:00Z'),
  ('seller-user-existing-001-${CASE_SUFFIX}', 'seller.${CASE_SUFFIX}@exists.com', 'seed', 'SELLER', 'ACTIVE', '2024-06-01T00:00:00Z');
INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES
  ('seller-existing-001-${CASE_SUFFIX}', 'seller-user-existing-001-${CASE_SUFFIX}', 'Existing Seller', 'Existing bio');
SQL
curl -sS -o "$LOGIN_FILE" -X POST "$BASE_URL/auth/login" \n  -H 'Content-Type: application/json' \n  --data "{"email":"$USER_EMAIL","password":"$USER_PASSWORD"}"
USER_TOKEN="$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$LOGIN_FILE")"
[ -n "$USER_TOKEN" ]

# When
HTTP_CODE="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/admin/sellers" -H "Authorization: Bearer $USER_TOKEN")"

# Then
[ "$HTTP_CODE" = "403" ]
grep -F '"error":"Forbidden"' "$RESPONSE_FILE" >/dev/null
echo 'CODEVALID_TEST_ASSERTION_OK:unauthorized_access_rejected'

# Cleanup
cleanup_db
trap - EXIT
