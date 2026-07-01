#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-stock-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-stock-${CASE_SUFFIX}"
PROD_IN_STOCK="prod-in-stock-${CASE_SUFFIX}"
PROD_OUT_OF_STOCK="prod-out-of-stock-${CASE_SUFFIX}"
PROD_NEGATIVE_STOCK="prod-negative-stock-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/in_stock_filter_shows_available_products_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/in_stock_filter_shows_available_products_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
cleanup_db() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id IN ('${PROD_IN_STOCK}','${PROD_OUT_OF_STOCK}','${PROD_NEGATIVE_STOCK}'); DELETE FROM seller_profiles WHERE id='${SELLER_PROFILE_ID}'; DELETE FROM users WHERE id='${SELLER_USER_ID}';" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', 'seller-stock-${CASE_SUFFIX}@example.com', '\$2b\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'SELLER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Stock Shop ${CASE_SUFFIX}', 'stock seller');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD_IN_STOCK}', '${SELLER_PROFILE_ID}', 'In Stock ${CASE_SUFFIX}', 'available item', 'electronics', 1000, 10, '[]', 'ACTIVE', true, NOW()),
  ('${PROD_OUT_OF_STOCK}', '${SELLER_PROFILE_ID}', 'Out Of Stock ${CASE_SUFFIX}', 'not available', 'electronics', 1000, 0, '[]', 'ACTIVE', true, NOW() - INTERVAL '1 hour'),
  ('${PROD_NEGATIVE_STOCK}', '${SELLER_PROFILE_ID}', 'Negative Stock ${CASE_SUFFIX}', 'invalid stock', 'electronics', 1000, -1, '[]', 'ACTIVE', true, NOW() - INTERVAL '2 hours');
" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products?in_stock=true" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
grep -F '"id":"'"$PROD_IN_STOCK"'"' "$RESPONSE_FILE" >/dev/null
! grep -F '"id":"'"$PROD_OUT_OF_STOCK"'"' "$RESPONSE_FILE" >/dev/null
! grep -F '"id":"'"$PROD_NEGATIVE_STOCK"'"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:in_stock_filter_shows_available_products"

# Cleanup
:
