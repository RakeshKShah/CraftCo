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
RESPONSE_FILE="/tmp/accumulated_sales_within_week_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/accumulated_sales_within_week_${CASE_SUFFIX}.status"
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
VALUES ('${SELLER_ID}', '${SELLER_USER_ID}', 'Weekly Aggregate ${CASE_SUFFIX}', 'weekly accumulation test');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at) VALUES
  ('product-601-${CASE_SUFFIX}', '${SELLER_ID}', 'Product 601 ${CASE_SUFFIX}', 'desc', 'misc', 2000, 5, '[]'::jsonb, 'ACTIVE', true, NOW()),
  ('product-602-${CASE_SUFFIX}', '${SELLER_ID}', 'Product 602 ${CASE_SUFFIX}', 'desc', 'misc', 3500, 5, '[]'::jsonb, 'ACTIVE', true, NOW()),
  ('product-603-${CASE_SUFFIX}', '${SELLER_ID}', 'Product 603 ${CASE_SUFFIX}', 'desc', 'misc', 8000, 5, '[]'::jsonb, 'ACTIVE', true, NOW()),
  ('product-604-${CASE_SUFFIX}', '${SELLER_ID}', 'Product 604 ${CASE_SUFFIX}', 'desc', 'misc', 15000, 5, '[]'::jsonb, 'ACTIVE', true, NOW()),
  ('product-605-${CASE_SUFFIX}', '${SELLER_ID}', 'Product 605 ${CASE_SUFFIX}', 'desc', 'misc', 21500, 5, '[]'::jsonb, 'ACTIVE', true, NOW());
INSERT INTO orders (id, buyer_id, status, total_cents, platform_fee_cents, created_at) VALUES
  ('order-601-${CASE_SUFFIX}', '${BUYER_ID}', 'PAID', 2000, 200, NOW() - INTERVAL '6 day'),
  ('order-602-${CASE_SUFFIX}', '${BUYER_ID}', 'PAID', 3500, 350, NOW() - INTERVAL '5 day'),
  ('order-603-${CASE_SUFFIX}', '${BUYER_ID}', 'PAID', 8000, 800, NOW() - INTERVAL '4 day'),
  ('order-604-${CASE_SUFFIX}', '${BUYER_ID}', 'PAID', 15000, 1500, NOW() - INTERVAL '3 day'),
  ('order-605-${CASE_SUFFIX}', '${BUYER_ID}', 'PAID', 21500, 2150, NOW() - INTERVAL '2 day');
INSERT INTO order_items (id, order_id, product_id, seller_id, qty, price_at_purchase, seller_payout_cents, payout_id) VALUES
  ('item-601-${CASE_SUFFIX}', 'order-601-${CASE_SUFFIX}', 'product-601-${CASE_SUFFIX}', '${SELLER_ID}', 1, 2000, 1800, NULL),
  ('item-602-${CASE_SUFFIX}', 'order-602-${CASE_SUFFIX}', 'product-602-${CASE_SUFFIX}', '${SELLER_ID}', 1, 3500, 3150, NULL),
  ('item-603-${CASE_SUFFIX}', 'order-603-${CASE_SUFFIX}', 'product-603-${CASE_SUFFIX}', '${SELLER_ID}', 1, 8000, 7200, NULL),
  ('item-604-${CASE_SUFFIX}', 'order-604-${CASE_SUFFIX}', 'product-604-${CASE_SUFFIX}', '${SELLER_ID}', 1, 15000, 13500, NULL),
  ('item-605-${CASE_SUFFIX}', 'order-605-${CASE_SUFFIX}', 'product-605-${CASE_SUFFIX}', '${SELLER_ID}', 1, 21500, 19350, NULL);
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/payouts/run" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H 'Content-Type: application/json' > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
grep -F '"processed":1' "$RESPONSE_FILE" >/dev/null
grep -F '"totalAmountCents":45000' "$RESPONSE_FILE" >/dev/null
PAYOUT_AMOUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT amount_cents FROM payouts WHERE seller_id = '${SELLER_ID}';")"
[ "$PAYOUT_AMOUNT" = "45000" ]
ITEMS_LINKED="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM order_items WHERE seller_id = '${SELLER_ID}' AND payout_id IS NOT NULL;")"
[ "$ITEMS_LINKED" = "5" ]
COMMISSION_TOTAL="$(psql "$DATABASE_URL" -t -A -c "SELECT SUM(price_at_purchase * qty - seller_payout_cents) FROM order_items WHERE seller_id = '${SELLER_ID}';")"
[ "$COMMISSION_TOTAL" = "5000" ]

echo "CODEVALID_TEST_ASSERTION_OK:accumulated_sales_within_week"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM order_items WHERE id IN ('item-601-${CASE_SUFFIX}','item-602-${CASE_SUFFIX}','item-603-${CASE_SUFFIX}','item-604-${CASE_SUFFIX}','item-605-${CASE_SUFFIX}');
DELETE FROM payouts WHERE seller_id = '${SELLER_ID}';
DELETE FROM orders WHERE id IN ('order-601-${CASE_SUFFIX}','order-602-${CASE_SUFFIX}','order-603-${CASE_SUFFIX}','order-604-${CASE_SUFFIX}','order-605-${CASE_SUFFIX}');
DELETE FROM products WHERE id IN ('product-601-${CASE_SUFFIX}','product-602-${CASE_SUFFIX}','product-603-${CASE_SUFFIX}','product-604-${CASE_SUFFIX}','product-605-${CASE_SUFFIX}');
DELETE FROM seller_profiles WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id IN ('${ADMIN_ID}','${SELLER_USER_ID}','${BUYER_ID}');
SQL
