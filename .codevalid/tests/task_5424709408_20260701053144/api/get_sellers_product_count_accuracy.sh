#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="get_sellers_product_count_accuracy"
TMP_DIR="$(mktemp -d)"
RESPONSE_FILE="$TMP_DIR/response.json"
LOGIN_FILE="$TMP_DIR/login.json"
ADMIN_ID="admin-${CASE_SUFFIX}"
ADMIN_EMAIL="${TEST_ID}.admin.${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD='AdminPass123!'
SELLER_USER_ID="u4-${CASE_SUFFIX}"
SELLER_PROFILE_ID="sp4-${CASE_SUFFIX}"
PASSWORD_HASH='\$2b\$10\$D0hUPmZl7Q3kN6lJzi10Suq5mN0eZZF9RnBbTK1ZBOqVaki3P6KyK'

cleanup_db() {
  psql "$DATABASE_URL" <<SQL >/dev/null 2>&1 || true
DELETE FROM products WHERE id IN ('prod-1-${CASE_SUFFIX}','prod-2-${CASE_SUFFIX}','prod-3-${CASE_SUFFIX}','prod-4-${CASE_SUFFIX}','prod-5-${CASE_SUFFIX}');
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id IN ('${SELLER_USER_ID}','${ADMIN_ID}');
SQL
  rm -rf "$TMP_DIR"
}
trap cleanup_db EXIT

# Given — seed one seller with exactly five associated products and an admin session user
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES
  ('${ADMIN_ID}', '${ADMIN_EMAIL}', '${PASSWORD_HASH}', 'ADMIN', 'ACTIVE', '2024-06-13T00:00:00Z'),
  ('${SELLER_USER_ID}', 'seller4.${CASE_SUFFIX}@example.com', '${PASSWORD_HASH}', 'SELLER', 'ACTIVE', '2024-01-05T07:00:00Z');

INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Productful Store', 'Has products');

INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('prod-1-${CASE_SUFFIX}', '${SELLER_PROFILE_ID}', 'Count Product 1', 'Desc 1', 'general', 1000, 1, ARRAY[]::text[], 'ACTIVE', true, '2024-01-05T08:00:00Z'),
  ('prod-2-${CASE_SUFFIX}', '${SELLER_PROFILE_ID}', 'Count Product 2', 'Desc 2', 'general', 1100, 1, ARRAY[]::text[], 'ACTIVE', true, '2024-01-05T08:01:00Z'),
  ('prod-3-${CASE_SUFFIX}', '${SELLER_PROFILE_ID}', 'Count Product 3', 'Desc 3', 'general', 1200, 1, ARRAY[]::text[], 'ACTIVE', true, '2024-01-05T08:02:00Z'),
  ('prod-4-${CASE_SUFFIX}', '${SELLER_PROFILE_ID}', 'Count Product 4', 'Desc 4', 'general', 1300, 1, ARRAY[]::text[], 'ACTIVE', true, '2024-01-05T08:03:00Z'),
  ('prod-5-${CASE_SUFFIX}', '${SELLER_PROFILE_ID}', 'Count Product 5', 'Desc 5', 'general', 1400, 1, ARRAY[]::text[], 'ACTIVE', true, '2024-01-05T08:04:00Z');
SQL

curl -sS -o "$LOGIN_FILE" -X POST "$BASE_URL/auth/login" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\"}"
ADMIN_TOKEN="$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$LOGIN_FILE")"
[ -n "$ADMIN_TOKEN" ]

# When — retrieve the admin seller list
HTTP_CODE="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/admin/sellers" \
  -H "Authorization: Bearer $ADMIN_TOKEN")"
BODY_MIN="$(tr -d '\n' < "$RESPONSE_FILE")"

# Then — assert the seeded seller reports product_count 5
[ "$HTTP_CODE" = "200" ]
printf '%s' "$BODY_MIN" | grep -F '"email":"seller4.' >/dev/null
printf '%s' "$BODY_MIN" | grep -F '@example.com","store_name":"Productful Store","bio":"Has products","status":"ACTIVE","product_count":5,"created_at":"2024-01-05T07:00:00.000Z"' >/dev/null
echo 'CODEVALID_TEST_ASSERTION_OK:get_sellers_product_count_accuracy'

# Cleanup — delete seeded products, profile, users, and temp files
cleanup_db
trap - EXIT
