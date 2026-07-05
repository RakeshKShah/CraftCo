#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
PRODUCT_ID="prod-reviews-pending-${CASE_SUFFIX}"
SELLER_ID="seller-reviews-pending-${CASE_SUFFIX}"
BUYER_ID="buyer-reviews-pending-${CASE_SUFFIX}"
ORDER_ID="order-reviews-pending-${CASE_SUFFIX}"
ORDER_ITEM_ID="order-item-reviews-pending-${CASE_SUFFIX}"
REVIEW_ID="rev-reviews-pending-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/reviews_only_from_completed_purchases_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/reviews_only_from_completed_purchases_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL
INSERT INTO users (id, email, password, role, name, created_at)
VALUES
  ('${SELLER_ID}', 'seller-pending-${CASE_SUFFIX}@example.com', 'pw-hash', 'SELLER', 'Seller Pending ${CASE_SUFFIX}', NOW()),
  ('${BUYER_ID}', 'carl-${CASE_SUFFIX}@example.com', 'pw-hash', 'BUYER', 'Carl ${CASE_SUFFIX}', NOW());

INSERT INTO seller_profiles (user_id, display_name, status)
VALUES ('${SELLER_ID}', 'Seller Pending ${CASE_SUFFIX}', 'APPROVED');

INSERT INTO products (id, seller_id, title, description, price_cents, stock, status, is_visible, created_at)
VALUES ('${PRODUCT_ID}', '${SELLER_ID}', 'Pending Review Product ${CASE_SUFFIX}', 'Product with non-delivered review fixture', 1899, 5, 'ACTIVE', true, NOW());

INSERT INTO orders (id, buyer_id, status, total_cents, created_at)
VALUES ('${ORDER_ID}', '${BUYER_ID}', 'PENDING', 1899, '2024-03-05T08:00:00Z');

INSERT INTO order_items (id, order_id, product_id, quantity, unit_price_cents)
VALUES ('${ORDER_ITEM_ID}', '${ORDER_ID}', '${PRODUCT_ID}', 1, 1899);

INSERT INTO reviews (id, order_item_id, product_id, buyer_id, rating, body, created_at)
VALUES ('${REVIEW_ID}', '${ORDER_ITEM_ID}', '${PRODUCT_ID}', '${BUYER_ID}', 3, 'Pending review', '2024-03-05T09:15:00Z');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/api/products/${PRODUCT_ID}/reviews" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
COUNT="$(jq 'length' "$RESPONSE_FILE")"
[ "$COUNT" = "1" ]
grep -F '"id":"'"${REVIEW_ID}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"body":"Pending review"' "$RESPONSE_FILE" >/dev/null
grep -F '"buyer_email":"ca***@example.com"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:reviews_only_from_completed_purchases"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM reviews WHERE id = '${REVIEW_ID}';
DELETE FROM order_items WHERE id = '${ORDER_ITEM_ID}';
DELETE FROM orders WHERE id = '${ORDER_ID}';
DELETE FROM products WHERE id = '${PRODUCT_ID}';
DELETE FROM seller_profiles WHERE user_id = '${SELLER_ID}';
DELETE FROM users WHERE id IN ('${SELLER_ID}', '${BUYER_ID}');
SQL
