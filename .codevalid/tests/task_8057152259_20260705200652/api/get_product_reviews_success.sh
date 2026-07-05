#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
PRODUCT_ID="prod-reviews-success-${CASE_SUFFIX}"
SELLER_ID="seller-reviews-success-${CASE_SUFFIX}"
BUYER_ONE_ID="buyer-reviews-success-a-${CASE_SUFFIX}"
BUYER_TWO_ID="buyer-reviews-success-b-${CASE_SUFFIX}"
ORDER_ONE_ID="order-reviews-success-a-${CASE_SUFFIX}"
ORDER_TWO_ID="order-reviews-success-b-${CASE_SUFFIX}"
ORDER_ITEM_ONE_ID="order-item-reviews-success-a-${CASE_SUFFIX}"
ORDER_ITEM_TWO_ID="order-item-reviews-success-b-${CASE_SUFFIX}"
REVIEW_ONE_ID="rev-reviews-success-a-${CASE_SUFFIX}"
REVIEW_TWO_ID="rev-reviews-success-b-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/get_product_reviews_success_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/get_product_reviews_success_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL
INSERT INTO users (id, email, password, role, name, created_at)
VALUES
  ('${SELLER_ID}', 'seller-${CASE_SUFFIX}@example.com', 'pw-hash', 'SELLER', 'Seller ${CASE_SUFFIX}', NOW()),
  ('${BUYER_ONE_ID}', 'alice-${CASE_SUFFIX}@example.com', 'pw-hash', 'BUYER', 'Alice ${CASE_SUFFIX}', NOW()),
  ('${BUYER_TWO_ID}', 'bob-${CASE_SUFFIX}@example.com', 'pw-hash', 'BUYER', 'Bob ${CASE_SUFFIX}', NOW());

INSERT INTO seller_profiles (user_id, display_name, status)
VALUES ('${SELLER_ID}', 'Seller ${CASE_SUFFIX}', 'APPROVED');

INSERT INTO products (id, seller_id, title, description, price_cents, stock, status, is_visible, created_at)
VALUES ('${PRODUCT_ID}', '${SELLER_ID}', 'Reviewable Product ${CASE_SUFFIX}', 'Product for review retrieval', 2599, 10, 'ACTIVE', true, NOW());

INSERT INTO orders (id, buyer_id, status, total_cents, created_at)
VALUES
  ('${ORDER_ONE_ID}', '${BUYER_ONE_ID}', 'DELIVERED', 2599, '2024-03-01T09:00:00Z'),
  ('${ORDER_TWO_ID}', '${BUYER_TWO_ID}', 'DELIVERED', 2599, '2024-03-02T11:00:00Z');

INSERT INTO order_items (id, order_id, product_id, quantity, unit_price_cents)
VALUES
  ('${ORDER_ITEM_ONE_ID}', '${ORDER_ONE_ID}', '${PRODUCT_ID}', 1, 2599),
  ('${ORDER_ITEM_TWO_ID}', '${ORDER_TWO_ID}', '${PRODUCT_ID}', 1, 2599);

INSERT INTO reviews (id, order_item_id, product_id, buyer_id, rating, body, created_at)
VALUES
  ('${REVIEW_ONE_ID}', '${ORDER_ITEM_ONE_ID}', '${PRODUCT_ID}', '${BUYER_ONE_ID}', 5, 'Great product!', '2024-03-01T10:00:00Z'),
  ('${REVIEW_TWO_ID}', '${ORDER_ITEM_TWO_ID}', '${PRODUCT_ID}', '${BUYER_TWO_ID}', 4, 'Good value', '2024-03-02T12:30:00Z');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/api/products/${PRODUCT_ID}/reviews" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
grep -F '"id":"'"${REVIEW_TWO_ID}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"id":"'"${REVIEW_ONE_ID}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"rating":4' "$RESPONSE_FILE" >/dev/null
grep -F '"rating":5' "$RESPONSE_FILE" >/dev/null
grep -F '"body":"Good value"' "$RESPONSE_FILE" >/dev/null
grep -F '"body":"Great product!"' "$RESPONSE_FILE" >/dev/null
grep -F '"buyer_email":"bo***@example.com"' "$RESPONSE_FILE" >/dev/null
grep -F '"buyer_email":"al***@example.com"' "$RESPONSE_FILE" >/dev/null
FIRST_REVIEW_ID="$(jq -r '.[0].id' "$RESPONSE_FILE")"
SECOND_REVIEW_ID="$(jq -r '.[1].id' "$RESPONSE_FILE")"
[ "$FIRST_REVIEW_ID" = "$REVIEW_TWO_ID" ]
[ "$SECOND_REVIEW_ID" = "$REVIEW_ONE_ID" ]
COUNT="$(jq 'length' "$RESPONSE_FILE")"
[ "$COUNT" = "2" ]

echo "CODEVALID_TEST_ASSERTION_OK:get_product_reviews_success"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM reviews WHERE id IN ('${REVIEW_ONE_ID}', '${REVIEW_TWO_ID}');
DELETE FROM order_items WHERE id IN ('${ORDER_ITEM_ONE_ID}', '${ORDER_ITEM_TWO_ID}');
DELETE FROM orders WHERE id IN ('${ORDER_ONE_ID}', '${ORDER_TWO_ID}');
DELETE FROM products WHERE id = '${PRODUCT_ID}';
DELETE FROM seller_profiles WHERE user_id = '${SELLER_ID}';
DELETE FROM users WHERE id IN ('${SELLER_ID}', '${BUYER_ONE_ID}', '${BUYER_TWO_ID}');
SQL
