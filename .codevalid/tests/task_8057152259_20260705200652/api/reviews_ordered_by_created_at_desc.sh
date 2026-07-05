#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
PRODUCT_ID="prod-reviews-order-${CASE_SUFFIX}"
SELLER_ID="seller-reviews-order-${CASE_SUFFIX}"
BUYER_ONE_ID="buyer-reviews-order-a-${CASE_SUFFIX}"
BUYER_TWO_ID="buyer-reviews-order-b-${CASE_SUFFIX}"
ORDER_ONE_ID="order-reviews-order-a-${CASE_SUFFIX}"
ORDER_TWO_ID="order-reviews-order-b-${CASE_SUFFIX}"
ORDER_ITEM_ONE_ID="order-item-reviews-order-a-${CASE_SUFFIX}"
ORDER_ITEM_TWO_ID="order-item-reviews-order-b-${CASE_SUFFIX}"
REVIEW_OLDER_ID="rev-reviews-order-old-${CASE_SUFFIX}"
REVIEW_NEWER_ID="rev-reviews-order-new-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/reviews_ordered_by_created_at_desc_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/reviews_ordered_by_created_at_desc_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL
INSERT INTO users (id, email, password, role, name, created_at)
VALUES
  ('${SELLER_ID}', 'seller-order-${CASE_SUFFIX}@example.com', 'pw-hash', 'SELLER', 'Seller Order ${CASE_SUFFIX}', NOW()),
  ('${BUYER_ONE_ID}', 'eve@example.com', 'pw-hash', 'BUYER', 'Eve ${CASE_SUFFIX}', NOW()),
  ('${BUYER_TWO_ID}', 'frank@example.com', 'pw-hash', 'BUYER', 'Frank ${CASE_SUFFIX}', NOW());

INSERT INTO seller_profiles (user_id, display_name, status)
VALUES ('${SELLER_ID}', 'Seller Order ${CASE_SUFFIX}', 'APPROVED');

INSERT INTO products (id, seller_id, title, description, price_cents, stock, status, is_visible, created_at)
VALUES ('${PRODUCT_ID}', '${SELLER_ID}', 'Ordered Review Product ${CASE_SUFFIX}', 'Product for ordering assertion', 3199, 12, 'ACTIVE', true, NOW());

INSERT INTO orders (id, buyer_id, status, total_cents, created_at)
VALUES
  ('${ORDER_ONE_ID}', '${BUYER_ONE_ID}', 'DELIVERED', 3199, '2024-02-20T07:00:00Z'),
  ('${ORDER_TWO_ID}', '${BUYER_TWO_ID}', 'DELIVERED', 3199, '2024-03-15T15:30:00Z');

INSERT INTO order_items (id, order_id, product_id, quantity, unit_price_cents)
VALUES
  ('${ORDER_ITEM_ONE_ID}', '${ORDER_ONE_ID}', '${PRODUCT_ID}', 1, 3199),
  ('${ORDER_ITEM_TWO_ID}', '${ORDER_TWO_ID}', '${PRODUCT_ID}', 1, 3199);

INSERT INTO reviews (id, order_item_id, product_id, buyer_id, rating, body, created_at)
VALUES
  ('${REVIEW_OLDER_ID}', '${ORDER_ITEM_ONE_ID}', '${PRODUCT_ID}', '${BUYER_ONE_ID}', 4, 'Older review', '2024-02-20T08:00:00Z'),
  ('${REVIEW_NEWER_ID}', '${ORDER_ITEM_TWO_ID}', '${PRODUCT_ID}', '${BUYER_TWO_ID}', 5, 'Newer review', '2024-03-15T16:45:00Z');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/api/products/${PRODUCT_ID}/reviews" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
FIRST_REVIEW_ID="$(jq -r '.[0].id' "$RESPONSE_FILE")"
SECOND_REVIEW_ID="$(jq -r '.[1].id' "$RESPONSE_FILE")"
[ "$FIRST_REVIEW_ID" = "$REVIEW_NEWER_ID" ]
[ "$SECOND_REVIEW_ID" = "$REVIEW_OLDER_ID" ]
grep -F '"buyer_email":"fr***@example.com"' "$RESPONSE_FILE" >/dev/null
grep -F '"buyer_email":"ev***@example.com"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:reviews_ordered_by_created_at_desc"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM reviews WHERE id IN ('${REVIEW_OLDER_ID}', '${REVIEW_NEWER_ID}');
DELETE FROM order_items WHERE id IN ('${ORDER_ITEM_ONE_ID}', '${ORDER_ITEM_TWO_ID}');
DELETE FROM orders WHERE id IN ('${ORDER_ONE_ID}', '${ORDER_TWO_ID}');
DELETE FROM products WHERE id = '${PRODUCT_ID}';
DELETE FROM seller_profiles WHERE user_id = '${SELLER_ID}';
DELETE FROM users WHERE id IN ('${SELLER_ID}', '${BUYER_ONE_ID}', '${BUYER_TWO_ID}');
SQL
