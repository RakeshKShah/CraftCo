#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_ID="admin-${CASE_SUFFIX}"
SELLER_USER_ID="seller-user-${CASE_SUFFIX}"
SELLER_ID="seller-${CASE_SUFFIX}"
BUYER_ID="buyer-${CASE_SUFFIX}"
ORDER1_ID="order-101-${CASE_SUFFIX}"
ORDER2_ID="order-102-${CASE_SUFFIX}"
ORDER3_ID="order-103-${CASE_SUFFIX}"
PRODUCT1_ID="product-101-${CASE_SUFFIX}"
PRODUCT2_ID="product-102-${CASE_SUFFIX}"
PRODUCT3_ID="product-103-${CASE_SUFFIX}"
ITEM1_ID="item-101-${CASE_SUFFIX}"
ITEM2_ID="item-102-${CASE_SUFFIX}"
ITEM3_ID="item-103-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/weekly_payout_processing_success_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/weekly_payout_processing_success_${CASE_SUFFIX}.status"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../../../../.." && pwd)"
ADMIN_TOKEN="$(cd "$REPO_ROOT/backend" && node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1], email: 'admin+'+process.argv[2]+'@example.com', role: 'ADMIN', status: 'ACTIVE'}, process.argv[3], {expiresIn: '7d'}));" "$ADMIN_ID" "$CASE_SUFFIX" "$JWT_SECRET")"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL
INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES
  ('${ADMIN_ID}', 'admin+${CASE_SUFFIX}@example.com', 'hash', 'ADMIN', 'ACTIVE', NOW()),
  ('${SELLER_USER_ID}', 'seller+${CASE_SUFFIX}@example.com', 'hash', 'SELLER', 'ACTIVE', NOW()),
  ('${BUYER_ID}', 'buyer+${CASE_SUFFIX}@example.com', 'hash', 'BUYER', 'ACTIVE', NOW());

INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_ID}', '${SELLER_USER_ID}', 'Weekly Store ${CASE_SUFFIX}', 'weekly payout test');

INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at) VALUES
  ('${PRODUCT1_ID}', '${SELLER_ID}', 'Product 101 ${CASE_SUFFIX}', 'desc', 'books', 10000, 10, '[]'::jsonb, 'ACTIVE', true, NOW()),
  ('${PRODUCT2_ID}', '${SELLER_ID}', 'Product 102 ${CASE_SUFFIX}', 'desc', 'books', 25000, 10, '[]'::jsonb, 'ACTIVE', true, NOW()),
  ('${PRODUCT3_ID}', '${SELLER_ID}', 'Product 103 ${CASE_SUFFIX}', 'desc', 'books', 5000, 10, '[]'::jsonb, 'ACTIVE', true, NOW());

INSERT INTO orders (id, buyer_id, status, total_cents, platform_fee_cents, created_at) VALUES
  ('${ORDER1_ID}', '${BUYER_ID}', 'PAID', 10000, 1000, NOW() - INTERVAL '2 day'),
  ('${ORDER2_ID}', '${BUYER_ID}', 'DELIVERED', 25000, 2500, NOW() - INTERVAL '3 day'),
  ('${ORDER3_ID}', '${BUYER_ID}', 'SHIPPED', 5000, 500, NOW() - INTERVAL '4 day');

INSERT INTO order_items (id, order_id, product_id, seller_id, qty, price_at_purchase, seller_payout_cents, payout_id) VALUES
  ('${ITEM1_ID}', '${ORDER1_ID}', '${PRODUCT1_ID}', '${SELLER_ID}', 1, 10000, 9000, NULL),
  ('${ITEM2_ID}', '${ORDER2_ID}', '${PRODUCT2_ID}', '${SELLER_ID}', 1, 25000, 22500, NULL),
  ('${ITEM3_ID}', '${ORDER3_ID}', '${PRODUCT3_ID}', '${SELLER_ID}', 1, 5000, 4500, NULL);
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/payouts/run" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H 'Content-Type: application/json' > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
grep -F '"processed":1' "$RESPONSE_FILE" >/dev/null
grep -F '"totalAmountCents":36000' "$RESPONSE_FILE" >/dev/null
grep -F '"demoMode":true' "$RESPONSE_FILE" >/dev/null
PAYOUT_ROW_COUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM payouts WHERE seller_id = '${SELLER_ID}' AND amount_cents = 36000 AND status = 'PENDING';")"
[ "$PAYOUT_ROW_COUNT" = "1" ]
CONNECTED_ITEMS="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM order_items WHERE id IN ('${ITEM1_ID}','${ITEM2_ID}','${ITEM3_ID}') AND payout_id IS NOT NULL;")"
[ "$CONNECTED_ITEMS" = "3" ]
PAYOUT_AMOUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT amount_cents FROM payouts WHERE seller_id = '${SELLER_ID}' LIMIT 1;")"
[ "$PAYOUT_AMOUNT" = "36000" ]
COMMISSION_TOTAL="$(psql "$DATABASE_URL" -t -A -c "SELECT SUM(price_at_purchase * qty - seller_payout_cents) FROM order_items WHERE id IN ('${ITEM1_ID}','${ITEM2_ID}','${ITEM3_ID}');")"
[ "$COMMISSION_TOTAL" = "4000" ]

echo "CODEVALID_TEST_ASSERTION_OK:weekly_payout_processing_success"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM order_items WHERE id IN ('${ITEM1_ID}','${ITEM2_ID}','${ITEM3_ID}');
DELETE FROM payouts WHERE seller_id = '${SELLER_ID}';
DELETE FROM orders WHERE id IN ('${ORDER1_ID}','${ORDER2_ID}','${ORDER3_ID}');
DELETE FROM products WHERE id IN ('${PRODUCT1_ID}','${PRODUCT2_ID}','${PRODUCT3_ID}');
DELETE FROM seller_profiles WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id IN ('${ADMIN_ID}','${SELLER_USER_ID}','${BUYER_ID}');
SQL
