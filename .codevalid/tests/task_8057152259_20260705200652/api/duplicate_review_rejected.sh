#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-/tmp/test_gen_ydh4e25v}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_ID="seller-review-duplicate-${CASE_SUFFIX}"
BUYER_ID="buyer-review-duplicate-${CASE_SUFFIX}"
PRODUCT_ID="prod-review-duplicate-${CASE_SUFFIX}"
ORDER_ID="order-review-duplicate-${CASE_SUFFIX}"
ORDER_ITEM_ID="item-review-duplicate-${CASE_SUFFIX}"
REVIEW_ID="review-review-duplicate-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/duplicate_review_rejected_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/duplicate_review_rejected_${CASE_SUFFIX}.status"
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
  ('${SELLER_ID}', 'seller-review-duplicate-${CASE_SUFFIX}@example.com', 'pw-hash', 'SELLER', 'Seller Review Duplicate ${CASE_SUFFIX}', NOW()),
  ('${BUYER_ID}', 'buyer-review-duplicate-${CASE_SUFFIX}@example.com', 'pw-hash', 'BUYER', 'Buyer Review Duplicate ${CASE_SUFFIX}', NOW());

INSERT INTO seller_profiles (user_id, display_name, status)
VALUES ('${SELLER_ID}', 'Seller Review Duplicate ${CASE_SUFFIX}', 'APPROVED');

INSERT INTO products (id, seller_id, title, description, price_cents, stock, status, is_visible, created_at)
VALUES ('${PRODUCT_ID}', '${SELLER_ID}', 'Duplicate Review Product ${CASE_SUFFIX}', 'Existing review fixture', 4099, 3, 'ACTIVE', true, NOW());

INSERT INTO orders (id, buyer_id, status, total_cents, created_at)
VALUES ('${ORDER_ID}', '${BUYER_ID}', 'DELIVERED', 4099, NOW());

INSERT INTO order_items (id, order_id, product_id, quantity, unit_price_cents)
VALUES ('${ORDER_ITEM_ID}', '${ORDER_ID}', '${PRODUCT_ID}', 1, 4099);

INSERT INTO reviews (id, order_item_id, product_id, buyer_id, rating, body, created_at)
VALUES ('${REVIEW_ID}', '${ORDER_ITEM_ID}', '${PRODUCT_ID}', '${BUYER_ID}', 5, 'Original review already stored', NOW());
SQL

AUTH_TOKEN="$(cd "$WORKSPACE_ROOT/backend" && make_buyer_token "$BUYER_ID")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/api/reviews" \
  -H "Authorization: Bearer ${AUTH_TOKEN}" \
  -H 'Content-Type: application/json' \
  --data "{\"order_item_id\":\"${ORDER_ITEM_ID}\",\"rating\":4,\"body\":\"Second review attempt\"}" \
  > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "400" ]
grep -F '"error":"Already reviewed"' "$RESPONSE_FILE" >/dev/null
REVIEW_COUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM reviews WHERE order_item_id = '${ORDER_ITEM_ID}';")"
[ "$REVIEW_COUNT" = "1" ]

echo "CODEVALID_TEST_ASSERTION_OK:duplicate_review_rejected"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM reviews WHERE order_item_id = '${ORDER_ITEM_ID}';
DELETE FROM order_items WHERE id = '${ORDER_ITEM_ID}';
DELETE FROM orders WHERE id = '${ORDER_ID}';
DELETE FROM products WHERE id = '${PRODUCT_ID}';
DELETE FROM seller_profiles WHERE user_id = '${SELLER_ID}';
DELETE FROM users WHERE id IN ('${SELLER_ID}', '${BUYER_ID}');
SQL
