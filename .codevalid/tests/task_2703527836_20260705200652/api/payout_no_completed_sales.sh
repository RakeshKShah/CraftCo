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
ORDER1_ID="order-pending-${CASE_SUFFIX}"
ORDER2_ID="order-old-${CASE_SUFFIX}"
PRODUCT1_ID="product-pending-${CASE_SUFFIX}"
PRODUCT2_ID="product-old-${CASE_SUFFIX}"
ITEM1_ID="item-pending-${CASE_SUFFIX}"
ITEM2_ID="item-old-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/payout_no_completed_sales_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/payout_no_completed_sales_${CASE_SUFFIX}.status"
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
VALUES ('${SELLER_ID}', '${SELLER_USER_ID}', 'No Sales Store ${CASE_SUFFIX}', 'no payout test');

INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at) VALUES
  ('${PRODUCT1_ID}', '${SELLER_ID}', 'Pending Product ${CASE_SUFFIX}', 'desc', 'misc', 50000, 5, '[]'::jsonb, 'ACTIVE', true, NOW()),
  ('${PRODUCT2_ID}', '${SELLER_ID}', 'Old Product ${CASE_SUFFIX}', 'desc', 'misc', 75000, 5, '[]'::jsonb, 'ACTIVE', true, NOW());

INSERT INTO orders (id, buyer_id, status, total_cents, platform_fee_cents, created_at) VALUES
  ('${ORDER1_ID}', '${BUYER_ID}', 'PENDING', 50000, 5000, NOW() - INTERVAL '2 day'),
  ('${ORDER2_ID}', '${BUYER_ID}', 'PAID', 75000, 7500, NOW() - INTERVAL '9 day');

INSERT INTO order_items (id, order_id, product_id, seller_id, qty, price_at_purchase, seller_payout_cents, payout_id) VALUES
  ('${ITEM1_ID}', '${ORDER1_ID}', '${PRODUCT1_ID}', '${SELLER_ID}', 1, 50000, 45000, NULL),
  ('${ITEM2_ID}', '${ORDER2_ID}', '${PRODUCT2_ID}', '${SELLER_ID}', 1, 75000, 67500, NULL);
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/payouts/run" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H 'Content-Type: application/json' > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
grep -F '"processed":0' "$RESPONSE_FILE" >/dev/null
grep -F '"totalAmountCents":0' "$RESPONSE_FILE" >/dev/null
grep -F '"demoMode":true' "$RESPONSE_FILE" >/dev/null
PAYOUT_COUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM payouts WHERE seller_id = '${SELLER_ID}';")"
[ "$PAYOUT_COUNT" = "0" ]
UNPAID_ITEMS="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM order_items WHERE id IN ('${ITEM1_ID}','${ITEM2_ID}') AND payout_id IS NULL;")"
[ "$UNPAID_ITEMS" = "2" ]

echo "CODEVALID_TEST_ASSERTION_OK:payout_no_completed_sales"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM order_items WHERE id IN ('${ITEM1_ID}','${ITEM2_ID}');
DELETE FROM orders WHERE id IN ('${ORDER1_ID}','${ORDER2_ID}');
DELETE FROM products WHERE id IN ('${PRODUCT1_ID}','${PRODUCT2_ID}');
DELETE FROM seller_profiles WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id IN ('${ADMIN_ID}','${SELLER_USER_ID}','${BUYER_ID}');
SQL
