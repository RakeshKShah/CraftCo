#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="suspended_seller_visible_in_admin_panel"
TMP_DIR="$(mktemp -d)"
RESPONSE_FILE="$TMP_DIR/response.json"
LOGIN_FILE="$TMP_DIR/login.json"
ADMIN_EMAIL="${TEST_ID}.admin.${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD='AdminPass123!'
SELLER_EMAIL="gone.${CASE_SUFFIX}@store.com"

cleanup_db() {
  psql "$DATABASE_URL" <<SQL >/dev/null 2>&1 || true
DELETE FROM products WHERE seller_id = 'seller-suspended-002-${CASE_SUFFIX}';
DELETE FROM seller_profiles WHERE id = 'seller-suspended-002-${CASE_SUFFIX}';
DELETE FROM users WHERE id IN ('admin-005-${CASE_SUFFIX}','user-suspended-002-${CASE_SUFFIX}');
SQL
  rm -rf "$TMP_DIR"
}
trap cleanup_db EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES
  ('admin-005-${CASE_SUFFIX}', '${ADMIN_EMAIL}', '\$2b\$10\$D0hUPmZl7Q3kN6lJzi10Suq5mN0eZZF9RnBbTK1ZBOqVaki3P6KyK', 'ADMIN', 'ACTIVE', '2024-04-01T00:00:00Z'),
  ('user-suspended-002-${CASE_SUFFIX}', '${SELLER_EMAIL}', 'seed', 'SELLER', 'SUSPENDED', '2024-04-02T00:00:00Z');
INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES
  ('seller-suspended-002-${CASE_SUFFIX}', 'user-suspended-002-${CASE_SUFFIX}', 'Suspended Market', 'No longer active');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at) VALUES
  ('prod-s1-${CASE_SUFFIX}', 'seller-suspended-002-${CASE_SUFFIX}', 'S1', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', false, '2024-04-02T10:00:00Z'),
  ('prod-s2-${CASE_SUFFIX}', 'seller-suspended-002-${CASE_SUFFIX}', 'S2', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', false, '2024-04-02T10:01:00Z'),
  ('prod-s3-${CASE_SUFFIX}', 'seller-suspended-002-${CASE_SUFFIX}', 'S3', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', false, '2024-04-02T10:02:00Z'),
  ('prod-s4-${CASE_SUFFIX}', 'seller-suspended-002-${CASE_SUFFIX}', 'S4', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', false, '2024-04-02T10:03:00Z'),
  ('prod-s5-${CASE_SUFFIX}', 'seller-suspended-002-${CASE_SUFFIX}', 'S5', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', false, '2024-04-02T10:04:00Z'),
  ('prod-s6-${CASE_SUFFIX}', 'seller-suspended-002-${CASE_SUFFIX}', 'S6', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', false, '2024-04-02T10:05:00Z'),
  ('prod-s7-${CASE_SUFFIX}', 'seller-suspended-002-${CASE_SUFFIX}', 'S7', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', false, '2024-04-02T10:06:00Z'),
  ('prod-s8-${CASE_SUFFIX}', 'seller-suspended-002-${CASE_SUFFIX}', 'S8', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', false, '2024-04-02T10:07:00Z'),
  ('prod-s9-${CASE_SUFFIX}', 'seller-suspended-002-${CASE_SUFFIX}', 'S9', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', false, '2024-04-02T10:08:00Z'),
  ('prod-s10-${CASE_SUFFIX}', 'seller-suspended-002-${CASE_SUFFIX}', 'S10', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', false, '2024-04-02T10:09:00Z');
SQL
curl -sS -o "$LOGIN_FILE" -X POST "$BASE_URL/auth/login" \n  -H 'Content-Type: application/json' \n  --data "{"email":"$ADMIN_EMAIL","password":"AdminPass123!"}"
ADMIN_TOKEN="$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$LOGIN_FILE")"
[ -n "$ADMIN_TOKEN" ]

# When
HTTP_CODE="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/admin/sellers" -H "Authorization: Bearer $ADMIN_TOKEN")"

# Then
[ "$HTTP_CODE" = "200" ]
grep -F ""id":"seller-suspended-002-${CASE_SUFFIX}"" "$RESPONSE_FILE" >/dev/null
grep -F '"status":"SUSPENDED"' "$RESPONSE_FILE" >/dev/null
grep -F '"product_count":10' "$RESPONSE_FILE" >/dev/null
echo 'CODEVALID_TEST_ASSERTION_OK:suspended_seller_visible_in_admin_panel'

# Cleanup
cleanup_db
trap - EXIT
