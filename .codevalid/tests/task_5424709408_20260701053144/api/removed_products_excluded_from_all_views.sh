#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_EMAIL="removed-admin-${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD="password"
ADMIN_ID="removed-admin-${CASE_SUFFIX}"
SELLER_USER_ID="removed-seller-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="removed-seller-profile-${CASE_SUFFIX}"
PROD_REMOVED_ID="prod-removed-${CASE_SUFFIX}"
PROD_ACTIVE_ID="prod-active-${CASE_SUFFIX}"
BUYER_RESPONSE_FILE="/tmp/removed_products_excluded_from_all_views_buyer_${CASE_SUFFIX}.json"
BUYER_STATUS_FILE="/tmp/removed_products_excluded_from_all_views_buyer_${CASE_SUFFIX}.status"
ADMIN_RESPONSE_FILE="/tmp/removed_products_excluded_from_all_views_admin_${CASE_SUFFIX}.json"
ADMIN_STATUS_FILE="/tmp/removed_products_excluded_from_all_views_admin_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$BUYER_RESPONSE_FILE" "$BUYER_STATUS_FILE" "$ADMIN_RESPONSE_FILE" "$ADMIN_STATUS_FILE"; }
cleanup_db() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id IN ('${PROD_REMOVED_ID}','${PROD_ACTIVE_ID}'); DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}'; DELETE FROM users WHERE id IN ('${ADMIN_ID}','${SELLER_USER_ID}');" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES
  ('${ADMIN_ID}', '${ADMIN_EMAIL}', '\$2b\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'ADMIN', 'ACTIVE', NOW()),
  ('${SELLER_USER_ID}', 'removed-seller-${CASE_SUFFIX}@example.com', 'x', 'SELLER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Removed Test Seller', 'bio');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD_REMOVED_ID}', '${SELLER_PROFILE_ID}', 'Deleted Item', 'removed product', 'ELECTRONICS', 1000, 5, '[]', 'REMOVED', true, NOW()),
  ('${PROD_ACTIVE_ID}', '${SELLER_PROFILE_ID}', 'Active Item', 'active product', 'ELECTRONICS', 1200, 5, '[]', 'ACTIVE', true, NOW() - INTERVAL '1 hour');
" >/dev/null
ADMIN_TOKEN="$(curl -sS -X POST "$BASE_URL/auth/login" -H 'Content-Type: application/json' -d '{"email":"'"$ADMIN_EMAIL"'","password":"'"$ADMIN_PASSWORD"'"}' | jq -r '.token')"
[ "$ADMIN_TOKEN" != "null" ]

# When
curl -sS -o "$BUYER_RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products" > "$BUYER_STATUS_FILE"
curl -sS -o "$ADMIN_RESPONSE_FILE" -w '%{http_code}' -H "Authorization: Bearer $ADMIN_TOKEN" "$BASE_URL/products" > "$ADMIN_STATUS_FILE"

# Then
[ "$(cat "$BUYER_STATUS_FILE")" = "200" ]
[ "$(cat "$ADMIN_STATUS_FILE")" = "200" ]
jq -e 'map(select(.id == "'"$PROD_REMOVED_ID"'")) | length == 0' "$BUYER_RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"$PROD_REMOVED_ID"'")) | length == 0' "$ADMIN_RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"$PROD_ACTIVE_ID"'")) | length == 1' "$BUYER_RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"$PROD_ACTIVE_ID"'")) | length == 1' "$ADMIN_RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:removed_products_excluded_from_all_views"

# Cleanup
:
