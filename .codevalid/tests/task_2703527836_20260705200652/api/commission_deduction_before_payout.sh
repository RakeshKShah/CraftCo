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
ORDER_ID="order-${CASE_SUFFIX}"
PRODUCT_ID="product-${CASE_SUFFIX}"
ITEM_ID="item-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/commission_deduction_before_payout_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/commission_deduction_before_payout_${CASE_SUFFIX}.status"
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
VALUES ('${SELLER_ID}', '${SELLER_USER_ID}', 'Commission Store ${CASE_SUFFIX}', 'commission test');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES ('${PRODUCT_ID}', '${SELLER_ID}', 'Commission Product ${CASE_SUFFIX}', 'desc', 'luxury', 100000, 2, '[]'::jsonb, 'ACTIVE', true, NOW());
INSERT INTO orders (id, buyer_id, status, total_cents, platform_fee_cents, created_at)
VALUES ('${ORDER_ID}', '${BUYER_ID}', 'PAID', 100000, 10000, NOW() - INTERVAL '2 day');
INSERT INTO order_items (id, order_id, product_id, seller_id, qty, price_at_purchase, seller_payout_cents, payout_id)
VALUES ('${ITEM_ID}', '${ORDER_ID}', '${PRODUCT_ID}', '${SELLER_ID}', 1, 100000, 90000, NULL);
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/payouts/run" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H 'Content-Type: application/json' > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
grep -F '"processed":1' "$RESPONSE_FILE" >/dev/null
grep -F '"totalAmountCents":90000' "$RESPONSE_FILE" >/dev/null
ITEM_PAYOUT="$(psql "$DATABASE_URL" -t -A -c "SELECT seller_payout_cents FROM order_items WHERE id = '${ITEM_ID}';")"
[ "$ITEM_PAYOUT" = "90000" ]
ORDER_FEE="$(psql "$DATABASE_URL" -t -A -c "SELECT platform_fee_cents FROM orders WHERE id = '${ORDER_ID}';")"
[ "$ORDER_FEE" = "10000" ]
PAYOUT_COUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM payouts WHERE seller_id = '${SELLER_ID}' AND amount_cents = 90000;")"
[ "$PAYOUT_COUNT" = "1" ]
ITEM_LINKED="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM order_items WHERE id = '${ITEM_ID}' AND payout_id IS NOT NULL;")"
[ "$ITEM_LINKED" = "1" ]

echo "CODEVALID_TEST_ASSERTION_OK:commission_deduction_before_payout"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM order_items WHERE id = '${ITEM_ID}';
DELETE FROM payouts WHERE seller_id = '${SELLER_ID}';
DELETE FROM orders WHERE id = '${ORDER_ID}';
DELETE FROM products WHERE id = '${PRODUCT_ID}';
DELETE FROM seller_profiles WHERE id = '${SELLER_ID}';
DELETE FROM users WHERE id IN ('${ADMIN_ID}','${SELLER_USER_ID}','${BUYER_ID}');
SQL
