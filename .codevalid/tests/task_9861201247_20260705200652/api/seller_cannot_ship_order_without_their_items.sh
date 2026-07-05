#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_ID="buyer-no-owned-items-${CASE_SUFFIX}"
REQUEST_SELLER_USER_ID="seller-user-no-owned-items-${CASE_SUFFIX}"
REQUEST_SELLER_PROFILE_ID="seller-profile-no-owned-items-${CASE_SUFFIX}"
OTHER_SELLER_USER_ID="seller-user-other-owned-items-${CASE_SUFFIX}"
OTHER_SELLER_PROFILE_ID="seller-profile-other-owned-items-${CASE_SUFFIX}"
PRODUCT_ID="product-no-owned-items-${CASE_SUFFIX}"
ORDER_ID="order-no-owned-items-${CASE_SUFFIX}"
ORDER_ITEM_ID="order-item-no-owned-items-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/seller_cannot_ship_order_without_their_items_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/seller_cannot_ship_order_without_their_items_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
SELLER_TOKEN="$(node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1], email: 'seller.no.owned.items+'+process.argv[2]+'@example.com', role: 'SELLER', status: 'ACTIVE', sellerProfileId: process.argv[3]}, 'dev-secret', {expiresIn:'7d'}));" "$REQUEST_SELLER_USER_ID" "$CASE_SUFFIX" "$REQUEST_SELLER_PROFILE_ID")"
psql "$DATABASE_URL" <<SQL
DELETE FROM "OrderItem" WHERE id = '${ORDER_ITEM_ID}';
DELETE FROM "Order" WHERE id = '${ORDER_ID}';
DELETE FROM "Product" WHERE id = '${PRODUCT_ID}';
DELETE FROM "SellerProfile" WHERE id IN ('${REQUEST_SELLER_PROFILE_ID}', '${OTHER_SELLER_PROFILE_ID}');
DELETE FROM "User" WHERE id IN ('${BUYER_ID}', '${REQUEST_SELLER_USER_ID}', '${OTHER_SELLER_USER_ID}');
INSERT INTO "User" (id, email, password, role, status, "createdAt") VALUES
  ('${BUYER_ID}', 'buyer.no.owned.items+${CASE_SUFFIX}@example.com', 'pw', 'BUYER', 'ACTIVE', NOW()),
  ('${REQUEST_SELLER_USER_ID}', 'seller.no.owned.items+${CASE_SUFFIX}@example.com', 'pw', 'SELLER', 'ACTIVE', NOW()),
  ('${OTHER_SELLER_USER_ID}', 'seller.other.owned.items+${CASE_SUFFIX}@example.com', 'pw', 'SELLER', 'ACTIVE', NOW());
INSERT INTO "SellerProfile" (id, "userId", "storeName", bio, status, "createdAt") VALUES
  ('${REQUEST_SELLER_PROFILE_ID}', '${REQUEST_SELLER_USER_ID}', 'Request Seller Store ${CASE_SUFFIX}', 'bio', 'ACTIVE', NOW()),
  ('${OTHER_SELLER_PROFILE_ID}', '${OTHER_SELLER_USER_ID}', 'Other Seller Store ${CASE_SUFFIX}', 'bio', 'ACTIVE', NOW());
INSERT INTO "Product" (id, title, description, price_cents, stock_qty, visible, status, "sellerId", category, "createdAt") VALUES
  ('${PRODUCT_ID}', 'Other Seller Product ${CASE_SUFFIX}', 'desc', 2399, 6, true, 'ACTIVE', '${OTHER_SELLER_PROFILE_ID}', 'general', NOW());
INSERT INTO "Order" (id, buyer_id, total_cents, platform_fee_cents, status, "createdAt") VALUES
  ('${ORDER_ID}', '${BUYER_ID}', 2399, 240, 'PAID', NOW());
INSERT INTO "OrderItem" (id, "orderId", "productId", "sellerId", qty, price_at_purchase, seller_payout_cents) VALUES
  ('${ORDER_ITEM_ID}', '${ORDER_ID}', '${PRODUCT_ID}', '${OTHER_SELLER_PROFILE_ID}', 1, 2399, 2159);
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/orders/${ORDER_ID}/ship" \
  -H "Authorization: Bearer ${SELLER_TOKEN}" \
  -H 'Content-Type: application/json' > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "403" ]
grep -F 'No items for your shop in this order' "$RESPONSE_FILE" >/dev/null
DB_STATUS="$(psql "$DATABASE_URL" -At -c "SELECT status FROM \"Order\" WHERE id = '${ORDER_ID}';")"
[ "$DB_STATUS" = 'PAID' ]
echo 'CODEVALID_TEST_ASSERTION_OK:seller_cannot_ship_order_without_their_items'

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM "OrderItem" WHERE id = '${ORDER_ITEM_ID}';
DELETE FROM "Order" WHERE id = '${ORDER_ID}';
DELETE FROM "Product" WHERE id = '${PRODUCT_ID}';
DELETE FROM "SellerProfile" WHERE id IN ('${REQUEST_SELLER_PROFILE_ID}', '${OTHER_SELLER_PROFILE_ID}');
DELETE FROM "User" WHERE id IN ('${BUYER_ID}', '${REQUEST_SELLER_USER_ID}', '${OTHER_SELLER_USER_ID}');
SQL
