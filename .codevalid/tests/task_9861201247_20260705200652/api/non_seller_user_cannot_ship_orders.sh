#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_ID="buyer-ship-forbidden-${CASE_SUFFIX}"
OTHER_BUYER_ID="buyer-order-owner-${CASE_SUFFIX}"
SELLER_USER_ID="seller-order-owner-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-order-owner-${CASE_SUFFIX}"
PRODUCT_ID="product-ship-forbidden-${CASE_SUFFIX}"
ORDER_ID="order-ship-forbidden-${CASE_SUFFIX}"
ORDER_ITEM_ID="order-item-ship-forbidden-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/non_seller_user_cannot_ship_orders_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/non_seller_user_cannot_ship_orders_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
BUYER_TOKEN="$(node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1], email: 'buyer.ship.forbidden+'+process.argv[2]+'@example.com', role: 'BUYER', status: 'ACTIVE'}, 'dev-secret', {expiresIn:'7d'}));" "$BUYER_ID" "$CASE_SUFFIX")"
psql "$DATABASE_URL" <<SQL
DELETE FROM "OrderItem" WHERE id = '${ORDER_ITEM_ID}';
DELETE FROM "Order" WHERE id = '${ORDER_ID}';
DELETE FROM "Product" WHERE id = '${PRODUCT_ID}';
DELETE FROM "SellerProfile" WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM "User" WHERE id IN ('${BUYER_ID}', '${OTHER_BUYER_ID}', '${SELLER_USER_ID}');
INSERT INTO "User" (id, email, password, role, status, "createdAt") VALUES
  ('${BUYER_ID}', 'buyer.ship.forbidden+${CASE_SUFFIX}@example.com', 'pw', 'BUYER', 'ACTIVE', NOW()),
  ('${OTHER_BUYER_ID}', 'buyer.order.owner+${CASE_SUFFIX}@example.com', 'pw', 'BUYER', 'ACTIVE', NOW()),
  ('${SELLER_USER_ID}', 'seller.order.owner+${CASE_SUFFIX}@example.com', 'pw', 'SELLER', 'ACTIVE', NOW());
INSERT INTO "SellerProfile" (id, "userId", "storeName", bio, status, "createdAt") VALUES
  ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Forbidden Ship Store ${CASE_SUFFIX}', 'bio', 'ACTIVE', NOW());
INSERT INTO "Product" (id, title, description, price_cents, stock_qty, visible, status, "sellerId", category, "createdAt") VALUES
  ('${PRODUCT_ID}', 'Forbidden Ship Product ${CASE_SUFFIX}', 'desc', 2099, 4, true, 'ACTIVE', '${SELLER_PROFILE_ID}', 'general', NOW());
INSERT INTO "Order" (id, buyer_id, total_cents, platform_fee_cents, status, "createdAt") VALUES
  ('${ORDER_ID}', '${OTHER_BUYER_ID}', 2099, 210, 'PAID', NOW());
INSERT INTO "OrderItem" (id, "orderId", "productId", "sellerId", qty, price_at_purchase, seller_payout_cents) VALUES
  ('${ORDER_ITEM_ID}', '${ORDER_ID}', '${PRODUCT_ID}', '${SELLER_PROFILE_ID}', 1, 2099, 1889);
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/orders/${ORDER_ID}/ship" \
  -H "Authorization: Bearer ${BUYER_TOKEN}" \
  -H 'Content-Type: application/json' > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "403" ]
grep -F 'Active seller required' "$RESPONSE_FILE" >/dev/null
DB_STATUS="$(psql "$DATABASE_URL" -At -c "SELECT status FROM \"Order\" WHERE id = '${ORDER_ID}';")"
[ "$DB_STATUS" = 'PAID' ]
echo 'CODEVALID_TEST_ASSERTION_OK:non_seller_user_cannot_ship_orders'

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM "OrderItem" WHERE id = '${ORDER_ITEM_ID}';
DELETE FROM "Order" WHERE id = '${ORDER_ID}';
DELETE FROM "Product" WHERE id = '${PRODUCT_ID}';
DELETE FROM "SellerProfile" WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM "User" WHERE id IN ('${BUYER_ID}', '${OTHER_BUYER_ID}', '${SELLER_USER_ID}');
SQL
