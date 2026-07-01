#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="seller_response_structure_validation"
TMP_DIR="$(mktemp -d)"
RESPONSE_FILE="$TMP_DIR/response.json"
LOGIN_FILE="$TMP_DIR/login.json"
ADMIN_EMAIL="${TEST_ID}.admin.${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD='AdminPass123!'
SELLER_EMAIL="seller.${CASE_SUFFIX}@test.com"

cleanup_db() {
  psql "$DATABASE_URL" <<SQL >/dev/null 2>&1 || true
DELETE FROM products WHERE seller_id = 'seller-002-${CASE_SUFFIX}';
DELETE FROM seller_profiles WHERE id = 'seller-002-${CASE_SUFFIX}';
DELETE FROM users WHERE id IN ('admin-002-${CASE_SUFFIX}','user-002-${CASE_SUFFIX}');
SQL
  rm -rf "$TMP_DIR"
}
trap cleanup_db EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES
  ('admin-002-${CASE_SUFFIX}', '${ADMIN_EMAIL}', '\$2b\$10\$D0hUPmZl7Q3kN6lJzi10Suq5mN0eZZF9RnBbTK1ZBOqVaki3P6KyK', 'ADMIN', 'ACTIVE', '2024-02-01T00:00:00Z'),
  ('user-002-${CASE_SUFFIX}', '${SELLER_EMAIL}', 'seed', 'SELLER', 'ACTIVE', '2024-02-02T03:04:05Z');
INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES
  ('seller-002-${CASE_SUFFIX}', 'user-002-${CASE_SUFFIX}', 'Test Store', 'Quality products here');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at) VALUES
  ('prod-1-${CASE_SUFFIX}', 'seller-002-${CASE_SUFFIX}', 'P1', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', true, '2024-02-02T12:00:00Z'),
  ('prod-2-${CASE_SUFFIX}', 'seller-002-${CASE_SUFFIX}', 'P2', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', true, '2024-02-02T12:01:00Z'),
  ('prod-3-${CASE_SUFFIX}', 'seller-002-${CASE_SUFFIX}', 'P3', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', true, '2024-02-02T12:02:00Z'),
  ('prod-4-${CASE_SUFFIX}', 'seller-002-${CASE_SUFFIX}', 'P4', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', true, '2024-02-02T12:03:00Z'),
  ('prod-5-${CASE_SUFFIX}', 'seller-002-${CASE_SUFFIX}', 'P5', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', true, '2024-02-02T12:04:00Z'),
  ('prod-6-${CASE_SUFFIX}', 'seller-002-${CASE_SUFFIX}', 'P6', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', true, '2024-02-02T12:05:00Z'),
  ('prod-7-${CASE_SUFFIX}', 'seller-002-${CASE_SUFFIX}', 'P7', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', true, '2024-02-02T12:06:00Z');
SQL
curl -sS -o "$LOGIN_FILE" -X POST "$BASE_URL/auth/login" \n  -H 'Content-Type: application/json' \n  --data "{"email":"$ADMIN_EMAIL","password":"AdminPass123!"}"
ADMIN_TOKEN="$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$LOGIN_FILE")"
[ -n "$ADMIN_TOKEN" ]

# When
HTTP_CODE="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/admin/sellers" -H "Authorization: Bearer $ADMIN_TOKEN")"

# Then
[ "$HTTP_CODE" = "200" ]
grep -F ""id":"seller-002-${CASE_SUFFIX}"" "$RESPONSE_FILE" >/dev/null
grep -F ""user_id":"user-002-${CASE_SUFFIX}"" "$RESPONSE_FILE" >/dev/null
grep -F ""email":"${SELLER_EMAIL}"" "$RESPONSE_FILE" >/dev/null
grep -F '"store_name":"Test Store"' "$RESPONSE_FILE" >/dev/null
grep -F '"bio":"Quality products here"' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"ACTIVE"' "$RESPONSE_FILE" >/dev/null
grep -F '"product_count":7' "$RESPONSE_FILE" >/dev/null
grep -E '"created_at":"[0-9]{4}-[0-9]{2}-[0-9]{2}T' "$RESPONSE_FILE" >/dev/null
echo 'CODEVALID_TEST_ASSERTION_OK:seller_response_structure_validation'

# Cleanup
cleanup_db
trap - EXIT
