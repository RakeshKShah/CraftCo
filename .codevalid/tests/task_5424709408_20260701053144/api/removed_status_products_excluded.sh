#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_EMAIL="admin-removed-${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD="password"
ADMIN_ID="admin-removed-${CASE_SUFFIX}"
SELLER_USER_ID="seller-removed-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-removed-${CASE_SUFFIX}"
PROD_REMOVED="prod-removed-${CASE_SUFFIX}"
PROD_ACTIVE="prod-active-${CASE_SUFFIX}"
BUYER_RESPONSE="/tmp/removed_status_products_excluded_buyer_${CASE_SUFFIX}.json"
BUYER_STATUS="/tmp/removed_status_products_excluded_buyer_${CASE_SUFFIX}.status"
ADMIN_RESPONSE="/tmp/removed_status_products_excluded_admin_${CASE_SUFFIX}.json"
ADMIN_STATUS="/tmp/removed_status_products_excluded_admin_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$BUYER_RESPONSE" "$BUYER_STATUS" "$ADMIN_RESPONSE" "$ADMIN_STATUS"; }
cleanup_db() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id IN ('${PROD_REMOVED}','${PROD_ACTIVE}'); DELETE FROM seller_profiles WHERE id='${SELLER_PROFILE_ID}'; DELETE FROM users WHERE id IN ('${ADMIN_ID}','${SELLER_USER_ID}');" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES
  ('${ADMIN_ID}', '${ADMIN_EMAIL}', '\$2b\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'ADMIN', 'ACTIVE', NOW()),
  ('${SELLER_USER_ID}', 'seller-removed-${CASE_SUFFIX}@example.com', '\$2b\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'SELLER', 'ACTIVE', NOW() - INTERVAL '1 day');
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Removed Shop ${CASE_SUFFIX}', 'removed seller');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD_REMOVED}', '${SELLER_PROFILE_ID}', 'Removed Product ${CASE_SUFFIX}', 'should never appear', 'electronics', 1000, 5, '[]', 'REMOVED', true, NOW()),
  ('${PROD_ACTIVE}', '${SELLER_PROFILE_ID}', 'Active Product ${CASE_SUFFIX}', 'should appear', 'electronics', 1000, 5, '[]', 'ACTIVE', true, NOW() - INTERVAL '1 hour');
" >/dev/null
ADMIN_TOKEN="$(curl -sS -X POST "$BASE_URL/auth/login" -H 'Content-Type: application/json' -d '{"email":"'"$ADMIN_EMAIL"'","password":"'"$ADMIN_PASSWORD"'"}' | jq -r '.token')"
[ "$ADMIN_TOKEN" != "null" ]

# When
curl -sS -o "$BUYER_RESPONSE" -w '%{http_code}' "$BASE_URL/products" > "$BUYER_STATUS"
curl -sS -o "$ADMIN_RESPONSE" -w '%{http_code}' -H "Authorization: Bearer $ADMIN_TOKEN" "$BASE_URL/products" > "$ADMIN_STATUS"

# Then
[ "$(cat "$BUYER_STATUS")" = "200" ]
[ "$(cat "$ADMIN_STATUS")" = "200" ]
! grep -F '"id":"'"$PROD_REMOVED"'"' "$BUYER_RESPONSE" >/dev/null
! grep -F '"id":"'"$PROD_REMOVED"'"' "$ADMIN_RESPONSE" >/dev/null
grep -F '"id":"'"$PROD_ACTIVE"'"' "$BUYER_RESPONSE" >/dev/null
grep -F '"id":"'"$PROD_ACTIVE"'"' "$ADMIN_RESPONSE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:removed_status_products_excluded"

# Cleanup
:
