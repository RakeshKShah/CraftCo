#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-/tmp/test_gen_ydh4e25v}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_ID="seller-create-review-success-${CASE_SUFFIX}"
BUYER_ID="buyer-create-review-success-${CASE_SUFFIX}"
PRODUCT_ID="prod-create-review-success-${CASE_SUFFIX}"
ORDER_ID="order-create-review-success-${CASE_SUFFIX}"
ORDER_ITEM_ID="order-item-create-review-success-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/create_review_success_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/create_review_success_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

make_buyer_token() {
  TEST_USER_ID="$1" node <<'NODE'
const jwt = require('jsonwebtoken');
const secret = process.env.JWT_SECRET || 'dev-secret';
process.stdout.write(jwt.sign({ id: process.env.TEST_USER_ID, role: 'BUYER' }, secret));
NODE
}

# Given
psql "$DATABASE_URL" <<SQL
INSERT INTO users (id, email, password, role, name, created_at)
VALUES
  ('${SELLER_ID}', 'seller-create-review-success-${CASE_SUFFIX}@example.com', 'pw-hash', 'SELLER', 'Seller Create Review Success ${CASE_SUFFIX}', NOW()),
  ('${BUYER_ID}', 'buyer-create-review-success-${CASE_SUFFIX}@example.com', 'pw-hash', 'BUYER', 'Buyer Create Review Success ${CASE_SUFFIX}', NOW());

INSERT INTO seller_profiles (user_id, display_name, status)
VALUES ('${SELLER_ID}', 'Seller Create Review Success ${CASE_SUFFIX}', 'APPROVED');

INSERT INTO products (id, seller_id, title, description, price_cents, stock, status, is_visible, created_at)
VALUES ('${PRODUCT_ID}', '${SELLER_ID}', 'Review Product ${CASE_SUFFIX}', 'Fixture for delivered review creation', 3299, 5, 'ACTIVE', true, NOW());

INSERT INTO orders (id, buyer_id, status, total_cents, created_at)
VALUES ('${ORDER_ID}', '${BUYER_ID}', 'DELIVERED', 3299, NOW());

INSERT INTO order_items (id, order_id, product_id, quantity, unit_price_cents)
VALUES ('${ORDER_ITEM_ID}', '${ORDER_ID}', '${PRODUCT_ID}', 1, 3299);
SQL

AUTH_TOKEN="$(cd "$WORKSPACE_ROOT/backend" && make_buyer_token "$BUYER_ID")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/api/reviews" \
  -H "Authorization: Bearer ${AUTH_TOKEN}" \
  -H 'Content-Type: application/json' \
  --data "{\"order_item_id\":\"${ORDER_ITEM_ID}\",\"rating\":5,\"body\":\"Excellent product, arrived on time!\"}" \
  > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "201" ]
ORDER_ITEM_ID="$ORDER_ITEM_ID" PRODUCT_ID="$PRODUCT_ID" BUYER_ID="$BUYER_ID" jq -e '.id and .orderItemId == env.ORDER_ITEM_ID and .productId == env.PRODUCT_ID and .buyerId == env.BUYER_ID and .rating == 5 and .body == "Excellent product, arrived on time!"' "$RESPONSE_FILE" >/dev/null
grep -F '"orderItemId":"'"${ORDER_ITEM_ID}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"productId":"'"${PRODUCT_ID}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"buyerId":"'"${BUYER_ID}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"rating":5' "$RESPONSE_FILE" >/dev/null
grep -F '"body":"Excellent product, arrived on time!"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:create_review_success"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM reviews WHERE order_item_id = '${ORDER_ITEM_ID}';
DELETE FROM order_items WHERE id = '${ORDER_ITEM_ID}';
DELETE FROM orders WHERE id = '${ORDER_ID}';
DELETE FROM products WHERE id = '${PRODUCT_ID}';
DELETE FROM seller_profiles WHERE user_id = '${SELLER_ID}';
DELETE FROM users WHERE id IN ('${SELLER_ID}', '${BUYER_ID}');
SQL
