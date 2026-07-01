#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-empty-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-empty-${CASE_SUFFIX}"
PROD_ID="prod-001-${CASE_SUFFIX}"
RESP_CATEGORY="/tmp/empty_result_when_no_matching_products_category_${CASE_SUFFIX}.json"
STATUS_CATEGORY="/tmp/empty_result_when_no_matching_products_category_${CASE_SUFFIX}.status"
RESP_KEYWORD="/tmp/empty_result_when_no_matching_products_keyword_${CASE_SUFFIX}.json"
STATUS_KEYWORD="/tmp/empty_result_when_no_matching_products_keyword_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESP_CATEGORY" "$STATUS_CATEGORY" "$RESP_KEYWORD" "$STATUS_KEYWORD"; }
cleanup_db() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id='${PROD_ID}'; DELETE FROM seller_profiles WHERE id='${SELLER_PROFILE_ID}'; DELETE FROM users WHERE id='${SELLER_USER_ID}';" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', 'seller-empty-${CASE_SUFFIX}@example.com', '\$2b\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'SELLER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Empty Shop ${CASE_SUFFIX}', 'empty seller');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES ('${PROD_ID}', '${SELLER_PROFILE_ID}', 'Existing Product ${CASE_SUFFIX}', 'visible electronics item', 'electronics', 1000, 5, '[]', 'ACTIVE', true, NOW());
" >/dev/null

# When
curl -sS -o "$RESP_CATEGORY" -w '%{http_code}' "$BASE_URL/products?category=nonexistent-category-${CASE_SUFFIX}" > "$STATUS_CATEGORY"
curl -sS -o "$RESP_KEYWORD" -w '%{http_code}' "$BASE_URL/products?keyword=xyzABC123nonexistent${CASE_SUFFIX}" > "$STATUS_KEYWORD"

# Then
[ "$(cat "$STATUS_CATEGORY")" = "200" ]
[ "$(cat "$STATUS_KEYWORD")" = "200" ]
[ "$(jq 'length' "$RESP_CATEGORY")" = "0" ]
[ "$(jq 'length' "$RESP_KEYWORD")" = "0" ]

echo "CODEVALID_TEST_ASSERTION_OK:empty_result_when_no_matching_products"

# Cleanup
:
