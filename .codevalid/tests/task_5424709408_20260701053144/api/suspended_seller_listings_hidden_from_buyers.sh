#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_EMAIL="admin-suspend-visibility-${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD="password"
ADMIN_ID="admin-suspend-visibility-${CASE_SUFFIX}"
SUSP_USER_ID="seller-suspended-user-${CASE_SUFFIX}"
SUSP_PROFILE_ID="seller-suspended-${CASE_SUFFIX}"
ACTIVE_USER_ID="seller-active-user-${CASE_SUFFIX}"
ACTIVE_PROFILE_ID="seller-active-${CASE_SUFFIX}"
PROD_SUSP_1="prod-suspended-1-${CASE_SUFFIX}"
PROD_SUSP_2="prod-suspended-2-${CASE_SUFFIX}"
PROD_ACTIVE="prod-active-${CASE_SUFFIX}"
BUYER_RESPONSE="/tmp/suspended_seller_listings_hidden_from_buyers_buyer_${CASE_SUFFIX}.json"
BUYER_STATUS="/tmp/suspended_seller_listings_hidden_from_buyers_buyer_${CASE_SUFFIX}.status"
ADMIN_RESPONSE="/tmp/suspended_seller_listings_hidden_from_buyers_admin_${CASE_SUFFIX}.json"
ADMIN_STATUS="/tmp/suspended_seller_listings_hidden_from_buyers_admin_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$BUYER_RESPONSE" "$BUYER_STATUS" "$ADMIN_RESPONSE" "$ADMIN_STATUS"; }
cleanup_db() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id IN ('${PROD_SUSP_1}','${PROD_SUSP_2}','${PROD_ACTIVE}'); DELETE FROM seller_profiles WHERE id IN ('${SUSP_PROFILE_ID}','${ACTIVE_PROFILE_ID}'); DELETE FROM users WHERE id IN ('${ADMIN_ID}','${SUSP_USER_ID}','${ACTIVE_USER_ID}');" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES
  ('${ADMIN_ID}', '${ADMIN_EMAIL}', '\$2b\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'ADMIN', 'ACTIVE', NOW()),
  ('${SUSP_USER_ID}', 'suspended-${CASE_SUFFIX}@example.com', '\$2b\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'SELLER', 'SUSPENDED', NOW() - INTERVAL '2 days'),
  ('${ACTIVE_USER_ID}', 'active-${CASE_SUFFIX}@example.com', '\$2b\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'SELLER', 'ACTIVE', NOW() - INTERVAL '1 day');
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES
  ('${SUSP_PROFILE_ID}', '${SUSP_USER_ID}', 'Suspended Seller ${CASE_SUFFIX}', 'suspended bio'),
  ('${ACTIVE_PROFILE_ID}', '${ACTIVE_USER_ID}', 'Active Seller ${CASE_SUFFIX}', 'active bio');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD_SUSP_1}', '${SUSP_PROFILE_ID}', 'Suspended Seller Product 1 ${CASE_SUFFIX}', 'hidden from buyers', 'electronics', 5000, 2, '[]', 'ACTIVE', false, NOW()),
  ('${PROD_SUSP_2}', '${SUSP_PROFILE_ID}', 'Suspended Seller Product 2 ${CASE_SUFFIX}', 'hidden from buyers', 'electronics', 6000, 3, '[]', 'ACTIVE', false, NOW() - INTERVAL '1 hour'),
  ('${PROD_ACTIVE}', '${ACTIVE_PROFILE_ID}', 'Active Product ${CASE_SUFFIX}', 'visible to buyers', 'electronics', 7000, 4, '[]', 'ACTIVE', true, NOW() - INTERVAL '2 hours');
" >/dev/null
ADMIN_TOKEN="$(curl -sS -X POST "$BASE_URL/auth/login" -H 'Content-Type: application/json' -d '{"email":"'"$ADMIN_EMAIL"'","password":"'"$ADMIN_PASSWORD"'"}' | jq -r '.token')"
[ "$ADMIN_TOKEN" != "null" ]

# When
curl -sS -o "$BUYER_RESPONSE" -w '%{http_code}' "$BASE_URL/products" > "$BUYER_STATUS"
curl -sS -o "$ADMIN_RESPONSE" -w '%{http_code}' -H "Authorization: Bearer $ADMIN_TOKEN" "$BASE_URL/products" > "$ADMIN_STATUS"

# Then
[ "$(cat "$BUYER_STATUS")" = "200" ]
[ "$(cat "$ADMIN_STATUS")" = "200" ]
! grep -F '"id":"'"$PROD_SUSP_1"'"' "$BUYER_RESPONSE" >/dev/null
! grep -F '"id":"'"$PROD_SUSP_2"'"' "$BUYER_RESPONSE" >/dev/null
grep -F '"id":"'"$PROD_ACTIVE"'"' "$BUYER_RESPONSE" >/dev/null
grep -F '"id":"'"$PROD_SUSP_1"'"' "$ADMIN_RESPONSE" >/dev/null
grep -F '"id":"'"$PROD_SUSP_2"'"' "$ADMIN_RESPONSE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:suspended_seller_listings_hidden_from_buyers"

# Cleanup
:
