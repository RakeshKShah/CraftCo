#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="pending_seller_visible_for_approval"
TMP_DIR="$(mktemp -d)"
RESPONSE_FILE="$TMP_DIR/response.json"
LOGIN_FILE="$TMP_DIR/login.json"
ADMIN_EMAIL="${TEST_ID}.admin.${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD='AdminPass123!'
PENDING_EMAIL="newapp.${CASE_SUFFIX}@store.com"

cleanup_db() {
  psql "$DATABASE_URL" <<SQL >/dev/null 2>&1 || true
DELETE FROM seller_profiles WHERE id = 'seller-pending-002-${CASE_SUFFIX}';
DELETE FROM users WHERE id IN ('admin-004-${CASE_SUFFIX}','user-pending-002-${CASE_SUFFIX}');
SQL
  rm -rf "$TMP_DIR"
}
trap cleanup_db EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES
  ('admin-004-${CASE_SUFFIX}', '${ADMIN_EMAIL}', '\$2b\$10\$D0hUPmZl7Q3kN6lJzi10Suq5mN0eZZF9RnBbTK1ZBOqVaki3P6KyK', 'ADMIN', 'ACTIVE', '2024-03-01T00:00:00Z'),
  ('user-pending-002-${CASE_SUFFIX}', '${PENDING_EMAIL}', 'seed', 'SELLER', 'PENDING', '2024-03-02T00:00:00Z');
INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES
  ('seller-pending-002-${CASE_SUFFIX}', 'user-pending-002-${CASE_SUFFIX}', 'New Applicant', 'Please approve my store');
SQL
curl -sS -o "$LOGIN_FILE" -X POST "$BASE_URL/auth/login" \n  -H 'Content-Type: application/json' \n  --data "{"email":"$ADMIN_EMAIL","password":"AdminPass123!"}"
ADMIN_TOKEN="$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$LOGIN_FILE")"
[ -n "$ADMIN_TOKEN" ]

# When
HTTP_CODE="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/admin/sellers" -H "Authorization: Bearer $ADMIN_TOKEN")"

# Then
[ "$HTTP_CODE" = "200" ]
COUNT="$(grep -o '"id":"seller-[^"]*' "$RESPONSE_FILE" | wc -l | tr -d ' ')"
[ "$COUNT" = "1" ]
grep -F '"status":"PENDING"' "$RESPONSE_FILE" >/dev/null
grep -F '"store_name":"New Applicant"' "$RESPONSE_FILE" >/dev/null
grep -F '"bio":"Please approve my store"' "$RESPONSE_FILE" >/dev/null
echo 'CODEVALID_TEST_ASSERTION_OK:pending_seller_visible_for_approval'

# Cleanup
cleanup_db
trap - EXIT
