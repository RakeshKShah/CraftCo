#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-category-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-category-${CASE_SUFFIX}"
PROD_ELECTRONICS="prod-electronics-${CASE_SUFFIX}"
PROD_BOOKS="prod-books-${CASE_SUFFIX}"
PROD_CLOTHING="prod-clothing-${CASE_SUFFIX}"
RESP_ELECTRONICS="/tmp/category_filter_applied_correctly_electronics_${CASE_SUFFIX}.json"
STATUS_ELECTRONICS="/tmp/category_filter_applied_correctly_electronics_${CASE_SUFFIX}.status"
RESP_BOOKS="/tmp/category_filter_applied_correctly_books_${CASE_SUFFIX}.json"
STATUS_BOOKS="/tmp/category_filter_applied_correctly_books_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESP_ELECTRONICS" "$STATUS_ELECTRONICS" "$RESP_BOOKS" "$STATUS_BOOKS"; }
cleanup_db() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id IN ('${PROD_ELECTRONICS}','${PROD_BOOKS}','${PROD_CLOTHING}'); DELETE FROM seller_profiles WHERE id='${SELLER_PROFILE_ID}'; DELETE FROM users WHERE id='${SELLER_USER_ID}';" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', 'seller-category-${CASE_SUFFIX}@example.com', '\$2b\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'SELLER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Category Shop ${CASE_SUFFIX}', 'category seller');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD_ELECTRONICS}', '${SELLER_PROFILE_ID}', 'Electronic Item ${CASE_SUFFIX}', 'electronics item', 'electronics', 1000, 5, '[]', 'ACTIVE', true, NOW()),
  ('${PROD_BOOKS}', '${SELLER_PROFILE_ID}', 'Book Item ${CASE_SUFFIX}', 'books item', 'books', 2000, 5, '[]', 'ACTIVE', true, NOW() - INTERVAL '1 hour'),
  ('${PROD_CLOTHING}', '${SELLER_PROFILE_ID}', 'Clothing Item ${CASE_SUFFIX}', 'clothing item', 'clothing', 3000, 5, '[]', 'ACTIVE', true, NOW() - INTERVAL '2 hours');
" >/dev/null

# When
curl -sS -o "$RESP_ELECTRONICS" -w '%{http_code}' "$BASE_URL/products?category=electronics" > "$STATUS_ELECTRONICS"
curl -sS -o "$RESP_BOOKS" -w '%{http_code}' "$BASE_URL/products?category=books" > "$STATUS_BOOKS"

# Then
[ "$(cat "$STATUS_ELECTRONICS")" = "200" ]
[ "$(cat "$STATUS_BOOKS")" = "200" ]
grep -F '"id":"'"$PROD_ELECTRONICS"'"' "$RESP_ELECTRONICS" >/dev/null
! grep -F '"id":"'"$PROD_BOOKS"'"' "$RESP_ELECTRONICS" >/dev/null
! grep -F '"id":"'"$PROD_CLOTHING"'"' "$RESP_ELECTRONICS" >/dev/null
grep -F '"id":"'"$PROD_BOOKS"'"' "$RESP_BOOKS" >/dev/null
! grep -F '"id":"'"$PROD_ELECTRONICS"'"' "$RESP_BOOKS" >/dev/null
! grep -F '"id":"'"$PROD_CLOTHING"'"' "$RESP_BOOKS" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:category_filter_applied_correctly"

# Cleanup
:
