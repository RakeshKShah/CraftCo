#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="product_count_accurate_per_seller"
TMP_DIR="$(mktemp -d)"
RESPONSE_FILE="$TMP_DIR/response.json"
LOGIN_FILE="$TMP_DIR/login.json"
ADMIN_EMAIL="${TEST_ID}.admin.${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD='AdminPass123!'

cleanup_db() {
  psql "$DATABASE_URL" <<SQL >/dev/null 2>&1 || true
DELETE FROM products WHERE seller_id IN ('seller-count-001-${CASE_SUFFIX}','seller-count-002-${CASE_SUFFIX}');
DELETE FROM seller_profiles WHERE id IN ('seller-count-001-${CASE_SUFFIX}','seller-count-002-${CASE_SUFFIX}');
DELETE FROM users WHERE id IN ('admin-006-${CASE_SUFFIX}','user-count-001-${CASE_SUFFIX}','user-count-002-${CASE_SUFFIX}');
SQL
  rm -rf "$TMP_DIR"
}
trap cleanup_db EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES
  ('admin-006-${CASE_SUFFIX}', '${ADMIN_EMAIL}', '\$2b\$10\$D0hUPmZl7Q3kN6lJzi10Suq5mN0eZZF9RnBbTK1ZBOqVaki3P6KyK', 'ADMIN', 'ACTIVE', '2024-05-01T00:00:00Z'),
  ('user-count-001-${CASE_SUFFIX}', 'zero.${CASE_SUFFIX}@store.com', 'seed', 'SELLER', 'ACTIVE', '2024-05-02T00:00:00Z'),
  ('user-count-002-${CASE_SUFFIX}', 'many.${CASE_SUFFIX}@store.com', 'seed', 'SELLER', 'ACTIVE', '2024-05-03T00:00:00Z');
INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES
  ('seller-count-001-${CASE_SUFFIX}', 'user-count-001-${CASE_SUFFIX}', 'Zero Products', 'Zero bio'),
  ('seller-count-002-${CASE_SUFFIX}', 'user-count-002-${CASE_SUFFIX}', 'Many Products', 'Many bio');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at) VALUES
  ('prod-m1-${CASE_SUFFIX}', 'seller-count-002-${CASE_SUFFIX}', 'M1', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', true, '2024-05-03T10:00:00Z'),
  ('prod-m2-${CASE_SUFFIX}', 'seller-count-002-${CASE_SUFFIX}', 'M2', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', true, '2024-05-03T10:01:00Z'),
  ('prod-m3-${CASE_SUFFIX}', 'seller-count-002-${CASE_SUFFIX}', 'M3', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', true, '2024-05-03T10:02:00Z'),
  ('prod-m4-${CASE_SUFFIX}', 'seller-count-002-${CASE_SUFFIX}', 'M4', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', true, '2024-05-03T10:03:00Z'),
  ('prod-m5-${CASE_SUFFIX}', 'seller-count-002-${CASE_SUFFIX}', 'M5', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', true, '2024-05-03T10:04:00Z'),
  ('prod-m6-${CASE_SUFFIX}', 'seller-count-002-${CASE_SUFFIX}', 'M6', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', true, '2024-05-03T10:05:00Z'),
  ('prod-m7-${CASE_SUFFIX}', 'seller-count-002-${CASE_SUFFIX}', 'M7', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', true, '2024-05-03T10:06:00Z'),
  ('prod-m8-${CASE_SUFFIX}', 'seller-count-002-${CASE_SUFFIX}', 'M8', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', true, '2024-05-03T10:07:00Z'),
  ('prod-m9-${CASE_SUFFIX}', 'seller-count-002-${CASE_SUFFIX}', 'M9', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', true, '2024-05-03T10:08:00Z'),
  ('prod-m10-${CASE_SUFFIX}', 'seller-count-002-${CASE_SUFFIX}', 'M10', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', true, '2024-05-03T10:09:00Z'),
  ('prod-m11-${CASE_SUFFIX}', 'seller-count-002-${CASE_SUFFIX}', 'M11', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', true, '2024-05-03T10:10:00Z'),
  ('prod-m12-${CASE_SUFFIX}', 'seller-count-002-${CASE_SUFFIX}', 'M12', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', true, '2024-05-03T10:11:00Z'),
  ('prod-m13-${CASE_SUFFIX}', 'seller-count-002-${CASE_SUFFIX}', 'M13', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', true, '2024-05-03T10:12:00Z'),
  ('prod-m14-${CASE_SUFFIX}', 'seller-count-002-${CASE_SUFFIX}', 'M14', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', true, '2024-05-03T10:13:00Z'),
  ('prod-m15-${CASE_SUFFIX}', 'seller-count-002-${CASE_SUFFIX}', 'M15', 'Desc', 'general', 1000, 1, '[]', 'ACTIVE', true, '2024-05-03T10:14:00Z');
SQL
curl -sS -o "$LOGIN_FILE" -X POST "$BASE_URL/auth/login" \n  -H 'Content-Type: application/json' \n  --data "{"email":"$ADMIN_EMAIL","password":"AdminPass123!"}"
ADMIN_TOKEN="$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$LOGIN_FILE")"
[ -n "$ADMIN_TOKEN" ]

# When
HTTP_CODE="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/admin/sellers" -H "Authorization: Bearer $ADMIN_TOKEN")"

# Then
[ "$HTTP_CODE" = "200" ]
grep -F ""id":"seller-count-001-${CASE_SUFFIX}"" "$RESPONSE_FILE" >/dev/null
grep -F ""id":"seller-count-002-${CASE_SUFFIX}"" "$RESPONSE_FILE" >/dev/null
grep -F '"product_count":0' "$RESPONSE_FILE" >/dev/null
grep -F '"product_count":15' "$RESPONSE_FILE" >/dev/null
echo 'CODEVALID_TEST_ASSERTION_OK:product_count_accurate_per_seller'

# Cleanup
cleanup_db
trap - EXIT
