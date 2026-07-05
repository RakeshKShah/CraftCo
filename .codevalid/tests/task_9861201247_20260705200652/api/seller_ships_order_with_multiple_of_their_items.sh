#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_ID="buyer-multi-ship-${CASE_SUFFIX}"
REQUEST_SELLER_USER_ID="seller-user-multi-ship-${CASE_SUFFIX}"
REQUEST_SELLER_PROFILE_ID="seller-profile-multi-ship-${CASE_SUFFIX}"
OTHER_SELLER_USER_ID="seller-user-multi-other-${CASE_SUFFIX}"
OTHER_SELLER_PROFILE_ID="seller-profile-multi-other-${CASE_SUFFIX}"
PRODUCT_ID_1="product-multi-ship-1-${CASE_SUFFIX}"
PRODUCT_ID_2="product-multi-ship-2-${CASE_SUFFIX}"
PRODUCT_ID_3="product-multi-ship-3-${CASE_SUFFIX}"
OTHER_PRODUCT_ID_1="product-multi-other-1-${CASE_SUFFIX}"
OTHER_PRODUCT_ID_2="product-multi-other-2-${CASE_SUFFIX}"
ORDER_ID="order-multi-ship-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/seller_ships_order_with_multiple_of_their_items_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/seller_ships_order_with_multiple_of_their_items_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
SELLER_TOKEN="$(node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1], email: 'seller.multi.ship+'+process.argv[2]+'@example.com', role: 'SELLER', status: 'ACTIVE', sellerProfileId: process.argv[3]}, 'dev-secret', {expiresIn:'7d'}));" "$REQUEST_SELLER_USER_ID" "$CASE_SUFFIX" "$REQUEST_SELLER_PROFILE_ID")"
psql "$DATABASE_URL" <<SQL
DELETE FROM "OrderItem" WHERE "orderId" = '${ORDER_ID}';
DELETE FROM "Order" WHERE id = '${ORDER_ID}';
DELETE FROM "Product" WHERE id IN ('${PRODUCT_ID_1}', '${PRODUCT_ID_2}', '${PRODUCT_ID_3}', '${OTHER_PRODUCT_ID_1}', '${OTHER_PRODUCT_ID_2}');
DELETE FROM "SellerProfile" WHERE id IN ('${REQUEST_SELLER_PROFILE_ID}', '${OTHER_SELLER_PROFILE_ID}');
DELETE FROM "User" WHERE id IN ('${BUYER_ID}', '${REQUEST_SELLER_USER_ID}', '${OTHER_SELLER_USER_ID}');
INSERT INTO "User" (id, email, password, role, status, "createdAt") VALUES
  ('${BUYER_ID}', 'buyer.multi.ship+${CASE_SUFFIX}@example.com', 'pw', 'BUYER', 'ACTIVE', NOW()),
  ('${REQUEST_SELLER_USER_ID}', 'seller.multi.ship+${CASE_SUFFIX}@example.com', 'pw', 'SELLER', 'ACTIVE', NOW()),
  ('${OTHER_SELLER_USER_ID}', 'seller.multi.other+${CASE_SUFFIX}@example.com', 'pw', 'SELLER', 'ACTIVE', NOW());
INSERT INTO "SellerProfile" (id, "userId", "storeName", bio, status, "createdAt") VALUES
  ('${REQUEST_SELLER_PROFILE_ID}', '${REQUEST_SELLER_USER_ID}', 'Multi Ship Store ${CASE_SUFFIX}', 'bio', 'ACTIVE', NOW()),
  ('${OTHER_SELLER_PROFILE_ID}', '${OTHER_SELLER_USER_ID}', 'Multi Other Store ${CASE_SUFFIX}', 'bio', 'ACTIVE', NOW());
INSERT INTO "Product" (id, title, description, price_cents, stock_qty, visible, status, "sellerId", category, "createdAt") VALUES
  ('${PRODUCT_ID_1}', 'Multi Ship Product 1 ${CASE_SUFFIX}', 'desc', 1500, 10, true, 'ACTIVE', '${REQUEST_SELLER_PROFILE_ID}', 'general', NOW()),
  ('${PRODUCT_ID_2}', 'Multi Ship Product 2 ${CASE_SUFFIX}', 'desc', 1600, 10, true, 'ACTIVE', '${REQUEST_SELLER_PROFILE_ID}', 'general', NOW()),
  ('${PRODUCT_ID_3}', 'Multi Ship Product 3 ${CASE_SUFFIX}', 'desc', 1700, 10, true, 'ACTIVE', '${REQUEST_SELLER_PROFILE_ID}', 'general', NOW()),
  ('${OTHER_PRODUCT_ID_1}', 'Multi Other Product 1 ${CASE_SUFFIX}', 'desc', 1800, 10, true, 'ACTIVE', '${OTHER_SELLER_PROFILE_ID}', 'general', NOW()),
  ('${OTHER_PRODUCT_ID_2}', 'Multi Other Product 2 ${CASE_SUFFIX}', 'desc', 1900, 10, true, 'ACTIVE', '${OTHER_SELLER_PROFILE_ID}', 'general', NOW());
INSERT INTO "Order" (id, buyer_id, total_cents, platform_fee_cents, status, "createdAt") VALUES
  ('${ORDER_ID}', '${BUYER_ID}', 8500, 850, 'PAID', NOW());
INSERT INTO "OrderItem" (id, "orderId", "productId", "sellerId", qty, price_at_purchase, seller_payout_cents) VALUES
  ('order-item-multi-1-${CASE_SUFFIX}', '${ORDER_ID}', '${PRODUCT_ID_1}', '${REQUEST_SELLER_PROFILE_ID}', 1, 1500, 1350),
  ('order-item-multi-2-${CASE_SUFFIX}', '${ORDER_ID}', '${PRODUCT_ID_2}', '${REQUEST_SELLER_PROFILE_ID}', 1, 1600, 1440),
  ('order-item-multi-3-${CASE_SUFFIX}', '${ORDER_ID}', '${PRODUCT_ID_3}', '${REQUEST_SELLER_PROFILE_ID}', 1, 1700, 1530),
  ('order-item-multi-4-${CASE_SUFFIX}', '${ORDER_ID}', '${OTHER_PRODUCT_ID_1}', '${OTHER_SELLER_PROFILE_ID}', 1, 1800, 1620),
  ('order-item-multi-5-${CASE_SUFFIX}', '${ORDER_ID}', '${OTHER_PRODUCT_ID_2}', '${OTHER_SELLER_PROFILE_ID}', 1, 1900, 1710);
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/orders/${ORDER_ID}/ship" \
  -H "Authorization: Bearer ${SELLER_TOKEN}" \
  -H 'Content-Type: application/json' > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
grep -F '"success":true' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"SHIPPED"' "$RESPONSE_FILE" >/dev/null
DB_STATUS="$(psql "$DATABASE_URL" -At -c "SELECT status FROM \"Order\" WHERE id = '${ORDER_ID}';")"
[ "$DB_STATUS" = 'SHIPPED' ]
echo 'CODEVALID_TEST_ASSERTION_OK:seller_ships_order_with_multiple_of_their_items'

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM "OrderItem" WHERE "orderId" = '${ORDER_ID}';
DELETE FROM "Order" WHERE id = '${ORDER_ID}';
DELETE FROM "Product" WHERE id IN ('${PRODUCT_ID_1}', '${PRODUCT_ID_2}', '${PRODUCT_ID_3}', '${OTHER_PRODUCT_ID_1}', '${OTHER_PRODUCT_ID_2}');
DELETE FROM "SellerProfile" WHERE id IN ('${REQUEST_SELLER_PROFILE_ID}', '${OTHER_SELLER_PROFILE_ID}');
DELETE FROM "User" WHERE id IN ('${BUYER_ID}', '${REQUEST_SELLER_USER_ID}', '${OTHER_SELLER_USER_ID}');
SQL
