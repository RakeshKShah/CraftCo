#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="get_sellers_happy_path_multiple_sellers"
TMP_DIR="$(mktemp -d)"
RESPONSE_FILE="$TMP_DIR/response.json"
LOGIN_FILE="$TMP_DIR/login.json"
ADMIN_ID="admin-${CASE_SUFFIX}"
ADMIN_EMAIL="${TEST_ID}.admin.${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD='AdminPass123!'
SELLER1_USER_ID="u1-${CASE_SUFFIX}"
SELLER1_PROFILE_ID="sp1-${CASE_SUFFIX}"
SELLER2_USER_ID="u2-${CASE_SUFFIX}"
SELLER2_PROFILE_ID="sp2-${CASE_SUFFIX}"
PASSWORD_HASH='\$2b\$10\$D0hUPmZl7Q3kN6lJzi10Suq5mN0eZZF9RnBbTK1ZBOqVaki3P6KyK'

cleanup_db() {
  psql "$DATABASE_URL" <<SQL >/dev/null 2>&1 || true
DELETE FROM products WHERE id IN ('prod-s1-a-${CASE_SUFFIX}','prod-s1-b-${CASE_SUFFIX}','prod-s1-c-${CASE_SUFFIX}','prod-s2-a-${CASE_SUFFIX}');
DELETE FROM seller_profiles WHERE id IN ('${SELLER1_PROFILE_ID}','${SELLER2_PROFILE_ID}');
DELETE FROM users WHERE id IN ('${SELLER1_USER_ID}','${SELLER2_USER_ID}','${ADMIN_ID}');
SQL
  rm -rf "$TMP_DIR"
}
trap cleanup_db EXIT

# Given — seed two sellers with store profile data and product counts, plus an admin for authenticated access
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${ADMIN_ID}', '${ADMIN_EMAIL}', '${PASSWORD_HASH}', 'ADMIN', 'ACTIVE', '2024-06-10T00:00:00Z');

INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES
  ('${SELLER1_USER_ID}', 'seller1.${CASE_SUFFIX}@example.com', '${PASSWORD_HASH}', 'SELLER', 'ACTIVE', '2024-01-02T10:00:00Z'),
  ('${SELLER2_USER_ID}', 'seller2.${CASE_SUFFIX}@example.com', '${PASSWORD_HASH}', 'SELLER', 'PENDING', '2024-01-03T09:00:00Z');

INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES
  ('${SELLER1_PROFILE_ID}', '${SELLER1_USER_ID}', 'Store One', 'Bio one'),
  ('${SELLER2_PROFILE_ID}', '${SELLER2_USER_ID}', 'Store Two', 'Bio two');

INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('prod-s1-a-${CASE_SUFFIX}', '${SELLER1_PROFILE_ID}', 'Seller1 Product A', 'Desc A', 'general', 1000, 3, ARRAY[]::text[], 'ACTIVE', true, '2024-01-02T11:00:00Z'),
  ('prod-s1-b-${CASE_SUFFIX}', '${SELLER1_PROFILE_ID}', 'Seller1 Product B', 'Desc B', 'general', 1100, 4, ARRAY[]::text[], 'ACTIVE', true, '2024-01-02T11:01:00Z'),
  ('prod-s1-c-${CASE_SUFFIX}', '${SELLER1_PROFILE_ID}', 'Seller1 Product C', 'Desc C', 'general', 1200, 5, ARRAY[]::text[], 'ACTIVE', true, '2024-01-02T11:02:00Z'),
  ('prod-s2-a-${CASE_SUFFIX}', '${SELLER2_PROFILE_ID}', 'Seller2 Product A', 'Desc D', 'general', 1300, 2, ARRAY[]::text[], 'ACTIVE', true, '2024-01-03T10:00:00Z');
SQL

curl -sS -o "$LOGIN_FILE" -X POST "$BASE_URL/auth/login" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\"}"
ADMIN_TOKEN="$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$LOGIN_FILE")"
[ -n "$ADMIN_TOKEN" ]

# When — request the admin seller management list
HTTP_CODE="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/admin/sellers" \
  -H "Authorization: Bearer $ADMIN_TOKEN")"
BODY_MIN="$(tr -d '\n' < "$RESPONSE_FILE")"
FIRST_EMAIL_LINE="$(grep -o '"email":"[^"]*@example.com"' "$RESPONSE_FILE" | sed -n '1p')"
SECOND_EMAIL_LINE="$(grep -o '"email":"[^"]*@example.com"' "$RESPONSE_FILE" | sed -n '2p')"

# Then — assert 200, descending created_at order, and required seller fields/values for both rows
[ "$HTTP_CODE" = "200" ]
printf '%s' "$BODY_MIN" | grep -F '"email":"seller2.' >/dev/null
printf '%s' "$BODY_MIN" | grep -F '@example.com","store_name":"Store Two","bio":"Bio two","status":"PENDING","product_count":1,"created_at":"2024-01-03T09:00:00.000Z"' >/dev/null
printf '%s' "$BODY_MIN" | grep -F '"email":"seller1.' >/dev/null
printf '%s' "$BODY_MIN" | grep -F '@example.com","store_name":"Store One","bio":"Bio one","status":"ACTIVE","product_count":3,"created_at":"2024-01-02T10:00:00.000Z"' >/dev/null
printf '%s' "$FIRST_EMAIL_LINE" | grep -F 'seller2.' >/dev/null
printf '%s' "$SECOND_EMAIL_LINE" | grep -F 'seller1.' >/dev/null
echo 'CODEVALID_TEST_ASSERTION_OK:get_sellers_happy_path_multiple_sellers'

# Cleanup — remove seeded products, seller profiles, users, and temp files
cleanup_db
trap - EXIT
