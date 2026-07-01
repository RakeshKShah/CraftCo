#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-combined-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-combined-${CASE_SUFFIX}"
PROD_MATCH="prod-match-all-${CASE_SUFFIX}"
PROD_WRONG_CATEGORY="prod-wrong-category-${CASE_SUFFIX}"
PROD_OUT_OF_STOCK="prod-out-of-stock-${CASE_SUFFIX}"
PROD_NO_KEYWORD="prod-no-keyword-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/combined_filters_applied_correctly_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/combined_filters_applied_correctly_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
cleanup_db() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id IN ('${PROD_MATCH}','${PROD_WRONG_CATEGORY}','${PROD_OUT_OF_STOCK}','${PROD_NO_KEYWORD}'); DELETE FROM seller_profiles WHERE id='${SELLER_PROFILE_ID}'; DELETE FROM users WHERE id='${SELLER_USER_ID}';" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', 'seller-combined-${CASE_SUFFIX}@example.com', '\$2b\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'SELLER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Combined Shop ${CASE_SUFFIX}', 'combined seller');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD_MATCH}', '${SELLER_PROFILE_ID}', 'Wireless Headphones ${CASE_SUFFIX}', 'wireless match item', 'electronics', 10000, 5, '[]', 'ACTIVE', true, NOW()),
  ('${PROD_WRONG_CATEGORY}', '${SELLER_PROFILE_ID}', 'Wireless Headphones Book ${CASE_SUFFIX}', 'wireless but wrong category', 'books', 10000, 5, '[]', 'ACTIVE', true, NOW() - INTERVAL '1 hour'),
  ('${PROD_OUT_OF_STOCK}', '${SELLER_PROFILE_ID}', 'Wireless Headphones Empty ${CASE_SUFFIX}', 'wireless but out of stock', 'electronics', 10000, 0, '[]', 'ACTIVE', true, NOW() - INTERVAL '2 hours'),
  ('${PROD_NO_KEYWORD}', '${SELLER_PROFILE_ID}', 'Bluetooth Speaker ${CASE_SUFFIX}', 'no matching keyword', 'electronics', 10000, 5, '[]', 'ACTIVE', true, NOW() - INTERVAL '3 hours');
" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products?category=electronics&keyword=wireless&in_stock=true" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
grep -F '"id":"'"$PROD_MATCH"'"' "$RESPONSE_FILE" >/dev/null
! grep -F '"id":"'"$PROD_WRONG_CATEGORY"'"' "$RESPONSE_FILE" >/dev/null
! grep -F '"id":"'"$PROD_OUT_OF_STOCK"'"' "$RESPONSE_FILE" >/dev/null
! grep -F '"id":"'"$PROD_NO_KEYWORD"'"' "$RESPONSE_FILE" >/dev/null
COUNT="$(jq 'length' "$RESPONSE_FILE")"
[ "$COUNT" = "1" ]

echo "CODEVALID_TEST_ASSERTION_OK:combined_filters_applied_correctly"

# Cleanup
:
