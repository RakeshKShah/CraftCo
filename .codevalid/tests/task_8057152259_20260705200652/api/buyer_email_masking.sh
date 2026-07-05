#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
PRODUCT_ID="prod-reviews-mask-${CASE_SUFFIX}"
SELLER_ID="seller-reviews-mask-${CASE_SUFFIX}"
BUYER_ID="buyer-reviews-mask-${CASE_SUFFIX}"
ORDER_ID="order-reviews-mask-${CASE_SUFFIX}"
ORDER_ITEM_ID="order-item-reviews-mask-${CASE_SUFFIX}"
REVIEW_ID="rev-reviews-mask-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/buyer_email_masking_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/buyer_email_masking_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL
INSERT INTO users (id, email, password, role, name, created_at)
VALUES
  ('${SELLER_ID}', 'seller-mask-${CASE_SUFFIX}@example.com', 'pw-hash', 'SELLER', 'Seller Mask ${CASE_SUFFIX}', NOW()),
  ('${BUYER_ID}', 'dianasn@example.com', 'pw-hash', 'BUYER', 'Diana ${CASE_SUFFIX}', NOW());

INSERT INTO seller_profiles (user_id, display_name, status)
VALUES ('${SELLER_ID}', 'Seller Mask ${CASE_SUFFIX}', 'APPROVED');

INSERT INTO products (id, seller_id, title, description, price_cents, stock, status, is_visible, created_at)
VALUES ('${PRODUCT_ID}', '${SELLER_ID}', 'Masking Product ${CASE_SUFFIX}', 'Product for masking assertion', 2099, 6, 'ACTIVE', true, NOW());

INSERT INTO orders (id, buyer_id, status, total_cents, created_at)
VALUES ('${ORDER_ID}', '${BUYER_ID}', 'DELIVERED', 2099, '2024-03-10T13:30:00Z');

INSERT INTO order_items (id, order_id, product_id, quantity, unit_price_cents)
VALUES ('${ORDER_ITEM_ID}', '${ORDER_ID}', '${PRODUCT_ID}', 1, 2099);

INSERT INTO reviews (id, order_item_id, product_id, buyer_id, rating, body, created_at)
VALUES ('${REVIEW_ID}', '${ORDER_ITEM_ID}', '${PRODUCT_ID}', '${BUYER_ID}', 5, 'Excellent', '2024-03-10T14:20:00Z');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/api/products/${PRODUCT_ID}/reviews" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
grep -F '"id":"'"${REVIEW_ID}"'"' "$RESPONSE_FILE" >/dev/null
MASKED_EMAIL="$(jq -r '.[0].buyer_email' "$RESPONSE_FILE")"
[ "$MASKED_EMAIL" = "di***@example.com" ]

echo "CODEVALID_TEST_ASSERTION_OK:buyer_email_masking"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM reviews WHERE id = '${REVIEW_ID}';
DELETE FROM order_items WHERE id = '${ORDER_ITEM_ID}';
DELETE FROM orders WHERE id = '${ORDER_ID}';
DELETE FROM products WHERE id = '${PRODUCT_ID}';
DELETE FROM seller_profiles WHERE user_id = '${SELLER_ID}';
DELETE FROM users WHERE id IN ('${SELLER_ID}', '${BUYER_ID}');
SQL
