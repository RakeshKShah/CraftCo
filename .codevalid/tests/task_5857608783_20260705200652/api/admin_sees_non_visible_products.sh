#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_EMAIL="admin-monitor-${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD="AdminPass123!"
ADMIN_USER_ID="admin-monitor-${CASE_SUFFIX}"
SELLER_USER_ID="seller-monitor-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-monitor-${CASE_SUFFIX}"
PROD1_ID="prod-601-${CASE_SUFFIX}"
PROD2_ID="prod-602-${CASE_SUFFIX}"
LOGIN_RESPONSE="/tmp/admin_sees_non_visible_products_login_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/admin_sees_non_visible_products_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/admin_sees_non_visible_products_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$LOGIN_RESPONSE" "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
ADMIN_HASH="$(node -e "console.log(require('bcryptjs').hashSync(process.argv[1], 10))" "$ADMIN_PASSWORD")"
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id IN ('${PROD1_ID}', '${PROD2_ID}');
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id IN ('${ADMIN_USER_ID}', '${SELLER_USER_ID}');
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES
  ('${ADMIN_USER_ID}', '${ADMIN_EMAIL}', '${ADMIN_HASH}', 'ADMIN', 'ACTIVE', NOW()),
  ('${SELLER_USER_ID}', 'seller-monitor-${CASE_SUFFIX}@example.com', 'seeded-hash', 'SELLER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Monitoring Store ${CASE_SUFFIX}', 'Seed data');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD1_ID}', '${SELLER_PROFILE_ID}', 'Public Product', 'Visible listing', 'General', 1200, 5, '[]'::jsonb, 'ACTIVE', true, NOW()),
  ('${PROD2_ID}', '${SELLER_PROFILE_ID}', 'Hidden Product', 'Hidden listing', 'General', 1300, 5, '[]'::jsonb, 'ACTIVE', false, NOW() + interval '1 second');
SQL
curl -sS -o "$LOGIN_RESPONSE" -X POST "$BASE_URL/auth/login" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\"}" >/dev/null
TOKEN="$(jq -r '.token' "$LOGIN_RESPONSE")"
[ "$TOKEN" != "null" ]
[ -n "$TOKEN" ]

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/products" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e 'length == 2' "$RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"${PROD1_ID}"'" and .visible == true)) | length == 1' "$RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"${PROD2_ID}"'" and .visible == false)) | length == 1' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:admin_sees_non_visible_products"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id IN ('${PROD1_ID}', '${PROD2_ID}');
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id IN ('${ADMIN_USER_ID}', '${SELLER_USER_ID}');
SQL
