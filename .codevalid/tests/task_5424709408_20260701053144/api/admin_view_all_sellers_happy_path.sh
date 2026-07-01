#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="admin_view_all_sellers_happy_path"
TMP_DIR="$(mktemp -d)"
RESPONSE_FILE="$TMP_DIR/response.json"
LOGIN_FILE="$TMP_DIR/login.json"
ADMIN_EMAIL="${TEST_ID}.admin.${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD='AdminPass123!'
PENDING_EMAIL="pending.${CASE_SUFFIX}@store.com"
ACTIVE_EMAIL="active.${CASE_SUFFIX}@store.com"
SUSPENDED_EMAIL="suspended.${CASE_SUFFIX}@store.com"

cleanup_db() {
  psql "$DATABASE_URL" <<SQL >/dev/null 2>&1 || true
DELETE FROM products WHERE seller_id IN ('seller-pending-${CASE_SUFFIX}','seller-approved-${CASE_SUFFIX}','seller-suspended-${CASE_SUFFIX}');
DELETE FROM seller_profiles WHERE id IN ('seller-pending-${CASE_SUFFIX}','seller-approved-${CASE_SUFFIX}','seller-suspended-${CASE_SUFFIX}');
DELETE FROM users WHERE id IN ('admin-${CASE_SUFFIX}','user-pending-${CASE_SUFFIX}','user-approved-${CASE_SUFFIX}','user-suspended-${CASE_SUFFIX}');
SQL
  rm -rf "$TMP_DIR"
}
trap cleanup_db EXIT

# Given
ADMIN_HASH='seed-admin-hash'
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES
  ('admin-${CASE_SUFFIX}', '${ADMIN_EMAIL}', '\$2b\$10\$D0hUPmZl7Q3kN6lJzi10Suq5mN0eZZF9RnBbTK1ZBOqVaki3P6KyK', 'ADMIN', 'ACTIVE', '2024-01-01T00:00:00Z'),
  ('user-pending-${CASE_SUFFIX}', '${PENDING_EMAIL}', 'seed', 'SELLER', 'PENDING', '2024-01-02T00:00:00Z'),
  ('user-approved-${CASE_SUFFIX}', '${ACTIVE_EMAIL}', 'seed', 'SELLER', 'ACTIVE', '2024-01-03T00:00:00Z'),
  ('user-suspended-${CASE_SUFFIX}', '${SUSPENDED_EMAIL}', 'seed', 'SELLER', 'SUSPENDED', '2024-01-04T00:00:00Z');
INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES
  ('seller-pending-${CASE_SUFFIX}', 'user-pending-${CASE_SUFFIX}', 'Pending Store', 'Waiting for approval'),
  ('seller-approved-${CASE_SUFFIX}', 'user-approved-${CASE_SUFFIX}', 'Active Store', 'Selling since 2023'),
  ('seller-suspended-${CASE_SUFFIX}', 'user-suspended-${CASE_SUFFIX}', 'Suspended Store', 'Account suspended');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at) VALUES
  ('prod-a1-${CASE_SUFFIX}', 'seller-approved-${CASE_SUFFIX}', 'A1', 'Desc', 'general', 1000, 10, '[]', 'ACTIVE', true, '2024-01-04T10:00:00Z'),
  ('prod-a2-${CASE_SUFFIX}', 'seller-approved-${CASE_SUFFIX}', 'A2', 'Desc', 'general', 1000, 10, '[]', 'ACTIVE', true, '2024-01-04T10:01:00Z'),
  ('prod-a3-${CASE_SUFFIX}', 'seller-approved-${CASE_SUFFIX}', 'A3', 'Desc', 'general', 1000, 10, '[]', 'ACTIVE', true, '2024-01-04T10:02:00Z'),
  ('prod-a4-${CASE_SUFFIX}', 'seller-approved-${CASE_SUFFIX}', 'A4', 'Desc', 'general', 1000, 10, '[]', 'ACTIVE', true, '2024-01-04T10:03:00Z'),
  ('prod-a5-${CASE_SUFFIX}', 'seller-approved-${CASE_SUFFIX}', 'A5', 'Desc', 'general', 1000, 10, '[]', 'ACTIVE', true, '2024-01-04T10:04:00Z'),
  ('prod-s1-${CASE_SUFFIX}', 'seller-suspended-${CASE_SUFFIX}', 'S1', 'Desc', 'general', 1000, 10, '[]', 'ACTIVE', false, '2024-01-04T11:00:00Z'),
  ('prod-s2-${CASE_SUFFIX}', 'seller-suspended-${CASE_SUFFIX}', 'S2', 'Desc', 'general', 1000, 10, '[]', 'ACTIVE', false, '2024-01-04T11:01:00Z'),
  ('prod-s3-${CASE_SUFFIX}', 'seller-suspended-${CASE_SUFFIX}', 'S3', 'Desc', 'general', 1000, 10, '[]', 'ACTIVE', false, '2024-01-04T11:02:00Z');
SQL
curl -sS -o "$LOGIN_FILE" -X POST "$BASE_URL/auth/login" \n  -H 'Content-Type: application/json' \n  --data "{"email":"$ADMIN_EMAIL","password":"AdminPass123!"}"
ADMIN_TOKEN="$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$LOGIN_FILE")"
[ -n "$ADMIN_TOKEN" ]

# When
HTTP_CODE="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/admin/sellers" -H "Authorization: Bearer $ADMIN_TOKEN")"

# Then
[ "$HTTP_CODE" = "200" ]
grep -F '"store_name":"Pending Store"' "$RESPONSE_FILE" >/dev/null
grep -F '"bio":"Waiting for approval"' "$RESPONSE_FILE" >/dev/null
grep -F '"store_name":"Active Store"' "$RESPONSE_FILE" >/dev/null
grep -F '"bio":"Selling since 2023"' "$RESPONSE_FILE" >/dev/null
grep -F '"store_name":"Suspended Store"' "$RESPONSE_FILE" >/dev/null
grep -F '"bio":"Account suspended"' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"PENDING"' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"ACTIVE"' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"SUSPENDED"' "$RESPONSE_FILE" >/dev/null
grep -F '"product_count":0' "$RESPONSE_FILE" >/dev/null
grep -F '"product_count":5' "$RESPONSE_FILE" >/dev/null
grep -F '"product_count":3' "$RESPONSE_FILE" >/dev/null
COUNT="$(grep -o '"id":"seller-[^"]*' "$RESPONSE_FILE" | wc -l | tr -d ' ')"
[ "$COUNT" = "3" ]
echo 'CODEVALID_TEST_ASSERTION_OK:admin_view_all_sellers_happy_path'

# Cleanup
cleanup_db
trap - EXIT
