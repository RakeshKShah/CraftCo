#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-keyword-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-keyword-${CASE_SUFFIX}"
PROD_1="prod-001-${CASE_SUFFIX}"
PROD_2="prod-002-${CASE_SUFFIX}"
PROD_3="prod-003-${CASE_SUFFIX}"
RESP_LOWER="/tmp/keyword_search_filters_products_lower_${CASE_SUFFIX}.json"
STATUS_LOWER="/tmp/keyword_search_filters_products_lower_${CASE_SUFFIX}.status"
RESP_UPPER="/tmp/keyword_search_filters_products_upper_${CASE_SUFFIX}.json"
STATUS_UPPER="/tmp/keyword_search_filters_products_upper_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESP_LOWER" "$STATUS_LOWER" "$RESP_UPPER" "$STATUS_UPPER"; }
cleanup_db() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id IN ('${PROD_1}','${PROD_2}','${PROD_3}'); DELETE FROM seller_profiles WHERE id='${SELLER_PROFILE_ID}'; DELETE FROM users WHERE id='${SELLER_USER_ID}';" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', 'seller-keyword-${CASE_SUFFIX}@example.com', '\$2b\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'SELLER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Keyword Shop ${CASE_SUFFIX}', 'keyword seller');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD_1}', '${SELLER_PROFILE_ID}', 'Wireless Mouse ${CASE_SUFFIX}', 'Ergonomic design', 'electronics', 2500, 10, '[]', 'ACTIVE', true, NOW()),
  ('${PROD_2}', '${SELLER_PROFILE_ID}', 'USB Keyboard ${CASE_SUFFIX}', 'Mechanical switches', 'electronics', 3500, 10, '[]', 'ACTIVE', true, NOW() - INTERVAL '1 hour'),
  ('${PROD_3}', '${SELLER_PROFILE_ID}', 'Webcam HD ${CASE_SUFFIX}', 'Wireless connection not available', 'electronics', 4500, 10, '[]', 'ACTIVE', true, NOW() - INTERVAL '2 hours');
" >/dev/null

# When
curl -sS -o "$RESP_LOWER" -w '%{http_code}' "$BASE_URL/products?keyword=wireless" > "$STATUS_LOWER"
curl -sS -o "$RESP_UPPER" -w '%{http_code}' "$BASE_URL/products?keyword=WIRELESS" > "$STATUS_UPPER"

# Then
[ "$(cat "$STATUS_LOWER")" = "200" ]
[ "$(cat "$STATUS_UPPER")" = "200" ]
grep -F '"id":"'"$PROD_1"'"' "$RESP_LOWER" >/dev/null
grep -F '"id":"'"$PROD_3"'"' "$RESP_LOWER" >/dev/null
! grep -F '"id":"'"$PROD_2"'"' "$RESP_LOWER" >/dev/null
LOWER_IDS="$(jq -r '.[].id' "$RESP_LOWER" | sort)"
UPPER_IDS="$(jq -r '.[].id' "$RESP_UPPER" | sort)"
[ "$LOWER_IDS" = "$UPPER_IDS" ]

echo "CODEVALID_TEST_ASSERTION_OK:keyword_search_filters_products"

# Cleanup
:
