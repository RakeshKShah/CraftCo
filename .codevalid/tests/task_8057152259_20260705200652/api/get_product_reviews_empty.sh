#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
PRODUCT_ID="prod-reviews-empty-${CASE_SUFFIX}"
SELLER_ID="seller-reviews-empty-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/get_product_reviews_empty_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/get_product_reviews_empty_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL
INSERT INTO users (id, email, password, role, name, created_at)
VALUES ('${SELLER_ID}', 'seller-empty-${CASE_SUFFIX}@example.com', 'pw-hash', 'SELLER', 'Seller Empty ${CASE_SUFFIX}', NOW());

INSERT INTO seller_profiles (user_id, display_name, status)
VALUES ('${SELLER_ID}', 'Seller Empty ${CASE_SUFFIX}', 'APPROVED');

INSERT INTO products (id, seller_id, title, description, price_cents, stock, status, is_visible, created_at)
VALUES ('${PRODUCT_ID}', '${SELLER_ID}', 'No Review Product ${CASE_SUFFIX}', 'Product without reviews', 1599, 8, 'ACTIVE', true, NOW());
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/api/products/${PRODUCT_ID}/reviews" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
COUNT="$(jq 'length' "$RESPONSE_FILE")"
[ "$COUNT" = "0" ]
[ "$(cat "$RESPONSE_FILE")" = "[]" ]

echo "CODEVALID_TEST_ASSERTION_OK:get_product_reviews_empty"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id = '${PRODUCT_ID}';
DELETE FROM seller_profiles WHERE user_id = '${SELLER_ID}';
DELETE FROM users WHERE id = '${SELLER_ID}';
SQL
