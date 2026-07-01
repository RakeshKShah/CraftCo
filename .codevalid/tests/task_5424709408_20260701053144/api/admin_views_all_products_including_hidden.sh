#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_EMAIL="admin-all-products-${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD="password"
ADMIN_ID="admin-all-products-${CASE_SUFFIX}"
SELLER_ACTIVE_USER_ID="seller-active-user-${CASE_SUFFIX}"
SELLER_ACTIVE_PROFILE_ID="seller-001-${CASE_SUFFIX}"
SELLER_SUSP_USER_ID="seller-susp-user-${CASE_SUFFIX}"
SELLER_SUSP_PROFILE_ID="seller-suspended-${CASE_SUFFIX}"
PROD_ACTIVE_ID="prod-active-${CASE_SUFFIX}"
PROD_HIDDEN_ID="prod-hidden-${CASE_SUFFIX}"
PROD_SUSP_ID="prod-suspended-seller-${CASE_SUFFIX}"
PROD_REMOVED_ID="prod-removed-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/admin_views_all_products_including_hidden_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/admin_views_all_products_including_hidden_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
cleanup_db() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id IN ('${PROD_ACTIVE_ID}','${PROD_HIDDEN_ID}','${PROD_SUSP_ID}','${PROD_REMOVED_ID}'); DELETE FROM seller_profiles WHERE id IN ('${SELLER_ACTIVE_PROFILE_ID}','${SELLER_SUSP_PROFILE_ID}'); DELETE FROM users WHERE id IN ('${ADMIN_ID}','${SELLER_ACTIVE_USER_ID}','${SELLER_SUSP_USER_ID}');" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES
  ('${ADMIN_ID}', '${ADMIN_EMAIL}', '\$2b\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'ADMIN', 'ACTIVE', NOW()),
  ('${SELLER_ACTIVE_USER_ID}', 'seller-active-${CASE_SUFFIX}@example.com', '\$2b\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'SELLER', 'ACTIVE', NOW() - INTERVAL '1 day'),
  ('${SELLER_SUSP_USER_ID}', 'seller-suspended-${CASE_SUFFIX}@example.com', '\$2b\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'SELLER', 'SUSPENDED', NOW() - INTERVAL '2 days');
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES
  ('${SELLER_ACTIVE_PROFILE_ID}', '${SELLER_ACTIVE_USER_ID}', 'Visible Shop ${CASE_SUFFIX}', 'active seller'),
  ('${SELLER_SUSP_PROFILE_ID}', '${SELLER_SUSP_USER_ID}', 'Suspended Shop ${CASE_SUFFIX}', 'suspended seller');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD_ACTIVE_ID}', '${SELLER_ACTIVE_PROFILE_ID}', 'Active Product ${CASE_SUFFIX}', 'visible item', 'electronics', 1000, 5, '[]', 'ACTIVE', true, NOW()),
  ('${PROD_HIDDEN_ID}', '${SELLER_ACTIVE_PROFILE_ID}', 'Hidden Product ${CASE_SUFFIX}', 'hidden item', 'electronics', 1100, 5, '[]', 'ACTIVE', false, NOW() - INTERVAL '1 hour'),
  ('${PROD_SUSP_ID}', '${SELLER_SUSP_PROFILE_ID}', 'Suspended Seller Product ${CASE_SUFFIX}', 'admin should still see', 'books', 1200, 5, '[]', 'ACTIVE', false, NOW() - INTERVAL '2 hours'),
  ('${PROD_REMOVED_ID}', '${SELLER_ACTIVE_PROFILE_ID}', 'Removed Product ${CASE_SUFFIX}', 'should never be listed', 'books', 1300, 5, '[]', 'REMOVED', true, NOW() - INTERVAL '3 hours');
" >/dev/null
ADMIN_TOKEN="$(curl -sS -X POST "$BASE_URL/auth/login" -H 'Content-Type: application/json' -d '{"email":"'"$ADMIN_EMAIL"'","password":"'"$ADMIN_PASSWORD"'"}' | jq -r '.token')"
[ "$ADMIN_TOKEN" != "null" ]

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -H "Authorization: Bearer $ADMIN_TOKEN" "$BASE_URL/products" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
grep -F '"id":"'"$PROD_ACTIVE_ID"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"id":"'"$PROD_HIDDEN_ID"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"id":"'"$PROD_SUSP_ID"'"' "$RESPONSE_FILE" >/dev/null
! grep -F '"id":"'"$PROD_REMOVED_ID"'"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:admin_views_all_products_including_hidden"

# Cleanup
:
