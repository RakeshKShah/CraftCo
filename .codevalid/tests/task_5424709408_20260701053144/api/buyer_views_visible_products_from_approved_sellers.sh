#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-user-approved-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-approved-${CASE_SUFFIX}"
PROD_ELECTRONICS_ID="prod-electronics-${CASE_SUFFIX}"
PROD_BOOKS_ID="prod-books-${CASE_SUFFIX}"
PROD_REMOVED_ID="prod-removed-${CASE_SUFFIX}"
BUYER_RESPONSE="/tmp/buyer_views_visible_products_from_approved_sellers_${CASE_SUFFIX}.json"
BUYER_STATUS="/tmp/buyer_views_visible_products_from_approved_sellers_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$BUYER_RESPONSE" "$BUYER_STATUS"; }
cleanup_db() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id IN ('${PROD_ELECTRONICS_ID}','${PROD_BOOKS_ID}','${PROD_REMOVED_ID}'); DELETE FROM seller_profiles WHERE id='${SELLER_PROFILE_ID}'; DELETE FROM users WHERE id='${SELLER_USER_ID}';" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', 'approved-seller-${CASE_SUFFIX}@example.com', '\$2b\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'SELLER', 'ACTIVE', NOW() - INTERVAL '1 day');
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Approved Electronics ${CASE_SUFFIX}', 'Visible seller bio');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD_ELECTRONICS_ID}', '${SELLER_PROFILE_ID}', 'Laptop Pro ${CASE_SUFFIX}', 'Electronics item ${CASE_SUFFIX}', 'electronics', 199999, 8, '[]', 'ACTIVE', true, NOW()),
  ('${PROD_BOOKS_ID}', '${SELLER_PROFILE_ID}', 'Python Guide ${CASE_SUFFIX}', 'Book item ${CASE_SUFFIX}', 'books', 2999, 20, '[]', 'ACTIVE', true, NOW() - INTERVAL '2 hours'),
  ('${PROD_REMOVED_ID}', '${SELLER_PROFILE_ID}', 'Removed Product ${CASE_SUFFIX}', 'Should not appear', 'electronics', 1234, 1, '[]', 'REMOVED', true, NOW() - INTERVAL '3 hours');
" >/dev/null

# When
curl -sS -o "$BUYER_RESPONSE" -w '%{http_code}' "$BASE_URL/products?category=electronics" > "$BUYER_STATUS"

# Then
[ "$(cat "$BUYER_STATUS")" = "200" ]
grep -F '"id":"'"$PROD_ELECTRONICS_ID"'"' "$BUYER_RESPONSE" >/dev/null
! grep -F '"id":"'"$PROD_BOOKS_ID"'"' "$BUYER_RESPONSE" >/dev/null
! grep -F '"id":"'"$PROD_REMOVED_ID"'"' "$BUYER_RESPONSE" >/dev/null
grep -F '"visible":true' "$BUYER_RESPONSE" >/dev/null
grep -F '"seller"' "$BUYER_RESPONSE" >/dev/null
FIRST_ID="$(jq -r '.[0].id' "$BUYER_RESPONSE")"
[ "$FIRST_ID" = "$PROD_ELECTRONICS_ID" ]

echo "CODEVALID_TEST_ASSERTION_OK:buyer_views_visible_products_from_approved_sellers"

# Cleanup
:
