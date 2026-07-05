#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_ID="buyer-inactive-ship-${CASE_SUFFIX}"
SELLER_USER_ID="seller-user-inactive-ship-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-inactive-ship-${CASE_SUFFIX}"
PRODUCT_ID="product-inactive-ship-${CASE_SUFFIX}"
ORDER_ID="order-inactive-ship-${CASE_SUFFIX}"
ORDER_ITEM_ID="order-item-inactive-ship-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/inactive_seller_cannot_ship_orders_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/inactive_seller_cannot_ship_orders_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
INACTIVE_SELLER_TOKEN="$(node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1], email: 'seller.inactive.ship+'+process.argv[2]+'@example.com', role: 'SELLER', status: 'INACTIVE', sellerProfileId: process.argv[3]}, 'dev-secret', {expiresIn:'7d'}));" "$SELLER_USER_ID" "$CASE_SUFFIX" "$SELLER_PROFILE_ID")"
psql "$DATABASE_URL" <<SQL
DELETE FROM "OrderItem" WHERE id = '${ORDER_ITEM_ID}';
DELETE FROM "Order" WHERE id = '${ORDER_ID}';
DELETE FROM "Product" WHERE id = '${PRODUCT_ID}';
DELETE FROM "SellerProfile" WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM "User" WHERE id IN ('${BUYER_ID}', '${SELLER_USER_ID}');
INSERT INTO "User" (id, email, password, role, status, "createdAt") VALUES
  ('${BUYER_ID}', 'buyer.inactive.ship+${CASE_SUFFIX}@example.com', 'pw', 'BUYER', 'ACTIVE', NOW()),
  ('${SELLER_USER_ID}', 'seller.inactive.ship+${CASE_SUFFIX}@example.com', 'pw', 'SELLER', 'INACTIVE', NOW());
INSERT INTO "SellerProfile" (id, "userId", "storeName", bio, status, "createdAt") VALUES
  ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Inactive Ship Store ${CASE_SUFFIX}', 'bio', 'INACTIVE', NOW());
INSERT INTO "Product" (id, title, description, price_cents, stock_qty, visible, status, "sellerId", category, "createdAt") VALUES
  ('${PRODUCT_ID}', 'Inactive Ship Product ${CASE_SUFFIX}', 'desc', 2199, 4, true, 'ACTIVE', '${SELLER_PROFILE_ID}', 'general', NOW());
INSERT INTO "Order" (id, buyer_id, total_cents, platform_fee_cents, status, "createdAt") VALUES
  ('${ORDER_ID}', '${BUYER_ID}', 2199, 220, 'PAID', NOW());
INSERT INTO "OrderItem" (id, "orderId", "productId", "sellerId", qty, price_at_purchase, seller_payout_cents) VALUES
  ('${ORDER_ITEM_ID}', '${ORDER_ID}', '${PRODUCT_ID}', '${SELLER_PROFILE_ID}', 1, 2199, 1979);
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/orders/${ORDER_ID}/ship" \
  -H "Authorization: Bearer ${INACTIVE_SELLER_TOKEN}" \
  -H 'Content-Type: application/json' > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "403" ]
grep -F 'Active seller required' "$RESPONSE_FILE" >/dev/null
DB_STATUS="$(psql "$DATABASE_URL" -At -c "SELECT status FROM \"Order\" WHERE id = '${ORDER_ID}';")"
[ "$DB_STATUS" = 'PAID' ]
echo 'CODEVALID_TEST_ASSERTION_OK:inactive_seller_cannot_ship_orders'

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM "OrderItem" WHERE id = '${ORDER_ITEM_ID}';
DELETE FROM "Order" WHERE id = '${ORDER_ID}';
DELETE FROM "Product" WHERE id = '${PRODUCT_ID}';
DELETE FROM "SellerProfile" WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM "User" WHERE id IN ('${BUYER_ID}', '${SELLER_USER_ID}');
SQL
