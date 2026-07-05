#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_ID="admin-${CASE_SUFFIX}"
BUYER_ID="buyer-${CASE_SUFFIX}"
SELLER1_USER_ID="seller1-user-${CASE_SUFFIX}"
SELLER2_USER_ID="seller2-user-${CASE_SUFFIX}"
SELLER3_USER_ID="seller3-user-${CASE_SUFFIX}"
SELLER1_ID="seller1-${CASE_SUFFIX}"
SELLER2_ID="seller2-${CASE_SUFFIX}"
SELLER3_ID="seller3-${CASE_SUFFIX}"
PRODUCT1_ID="product1-${CASE_SUFFIX}"
PRODUCT2_ID="product2-${CASE_SUFFIX}"
PRODUCT3_ID="product3-${CASE_SUFFIX}"
ORDER1_ID="order1-${CASE_SUFFIX}"
ORDER2_ID="order2-${CASE_SUFFIX}"
ORDER3_ID="order3-${CASE_SUFFIX}"
ITEM1_ID="item1-${CASE_SUFFIX}"
ITEM2_ID="item2-${CASE_SUFFIX}"
ITEM3_ID="item3-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/multiple_sellers_single_payout_run_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/multiple_sellers_single_payout_run_${CASE_SUFFIX}.status"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../../../../.." && pwd)"
ADMIN_TOKEN="$(cd "$REPO_ROOT/backend" && node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1], email: 'admin+'+process.argv[2]+'@example.com', role: 'ADMIN', status: 'ACTIVE'}, process.argv[3], {expiresIn: '7d'}));" "$ADMIN_ID" "$CASE_SUFFIX" "$JWT_SECRET")"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL
INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES
  ('${ADMIN_ID}', 'admin+${CASE_SUFFIX}@example.com', 'hash', 'ADMIN', 'ACTIVE', NOW()),
  ('${BUYER_ID}', 'buyer+${CASE_SUFFIX}@example.com', 'hash', 'BUYER', 'ACTIVE', NOW()),
  ('${SELLER1_USER_ID}', 'seller1+${CASE_SUFFIX}@example.com', 'hash', 'SELLER', 'ACTIVE', NOW()),
  ('${SELLER2_USER_ID}', 'seller2+${CASE_SUFFIX}@example.com', 'hash', 'SELLER', 'ACTIVE', NOW()),
  ('${SELLER3_USER_ID}', 'seller3+${CASE_SUFFIX}@example.com', 'hash', 'SELLER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES
  ('${SELLER1_ID}', '${SELLER1_USER_ID}', 'Store 1 ${CASE_SUFFIX}', 'multi seller 1'),
  ('${SELLER2_ID}', '${SELLER2_USER_ID}', 'Store 2 ${CASE_SUFFIX}', 'multi seller 2'),
  ('${SELLER3_ID}', '${SELLER3_USER_ID}', 'Store 3 ${CASE_SUFFIX}', 'multi seller 3');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at) VALUES
  ('${PRODUCT1_ID}', '${SELLER1_ID}', 'Product 1 ${CASE_SUFFIX}', 'desc', 'misc', 20000, 3, '[]'::jsonb, 'ACTIVE', true, NOW()),
  ('${PRODUCT2_ID}', '${SELLER2_ID}', 'Product 2 ${CASE_SUFFIX}', 'desc', 'misc', 40000, 3, '[]'::jsonb, 'ACTIVE', true, NOW()),
  ('${PRODUCT3_ID}', '${SELLER3_ID}', 'Product 3 ${CASE_SUFFIX}', 'desc', 'misc', 60000, 3, '[]'::jsonb, 'ACTIVE', true, NOW());
INSERT INTO orders (id, buyer_id, status, total_cents, platform_fee_cents, created_at) VALUES
  ('${ORDER1_ID}', '${BUYER_ID}', 'PAID', 20000, 2000, NOW() - INTERVAL '2 day'),
  ('${ORDER2_ID}', '${BUYER_ID}', 'PAID', 40000, 4000, NOW() - INTERVAL '3 day'),
  ('${ORDER3_ID}', '${BUYER_ID}', 'PAID', 60000, 6000, NOW() - INTERVAL '4 day');
INSERT INTO order_items (id, order_id, product_id, seller_id, qty, price_at_purchase, seller_payout_cents, payout_id) VALUES
  ('${ITEM1_ID}', '${ORDER1_ID}', '${PRODUCT1_ID}', '${SELLER1_ID}', 1, 20000, 18000, NULL),
  ('${ITEM2_ID}', '${ORDER2_ID}', '${PRODUCT2_ID}', '${SELLER2_ID}', 1, 40000, 36000, NULL),
  ('${ITEM3_ID}', '${ORDER3_ID}', '${PRODUCT3_ID}', '${SELLER3_ID}', 1, 60000, 54000, NULL);
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/payouts/run" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H 'Content-Type: application/json' > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
grep -F '"processed":3' "$RESPONSE_FILE" >/dev/null
grep -F '"totalAmountCents":108000' "$RESPONSE_FILE" >/dev/null
P1="$(psql "$DATABASE_URL" -t -A -c "SELECT amount_cents FROM payouts WHERE seller_id = '${SELLER1_ID}';")"
P2="$(psql "$DATABASE_URL" -t -A -c "SELECT amount_cents FROM payouts WHERE seller_id = '${SELLER2_ID}';")"
P3="$(psql "$DATABASE_URL" -t -A -c "SELECT amount_cents FROM payouts WHERE seller_id = '${SELLER3_ID}';")"
[ "$P1" = "18000" ]
[ "$P2" = "36000" ]
[ "$P3" = "54000" ]
TOTAL_COMMISSION="$(psql "$DATABASE_URL" -t -A -c "SELECT SUM(price_at_purchase * qty - seller_payout_cents) FROM order_items WHERE id IN ('${ITEM1_ID}','${ITEM2_ID}','${ITEM3_ID}');")"
[ "$TOTAL_COMMISSION" = "12000" ]

echo "CODEVALID_TEST_ASSERTION_OK:multiple_sellers_single_payout_run"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM order_items WHERE id IN ('${ITEM1_ID}','${ITEM2_ID}','${ITEM3_ID}');
DELETE FROM payouts WHERE seller_id IN ('${SELLER1_ID}','${SELLER2_ID}','${SELLER3_ID}');
DELETE FROM orders WHERE id IN ('${ORDER1_ID}','${ORDER2_ID}','${ORDER3_ID}');
DELETE FROM products WHERE id IN ('${PRODUCT1_ID}','${PRODUCT2_ID}','${PRODUCT3_ID}');
DELETE FROM seller_profiles WHERE id IN ('${SELLER1_ID}','${SELLER2_ID}','${SELLER3_ID}');
DELETE FROM users WHERE id IN ('${ADMIN_ID}','${BUYER_ID}','${SELLER1_USER_ID}','${SELLER2_USER_ID}','${SELLER3_USER_ID}');
SQL
