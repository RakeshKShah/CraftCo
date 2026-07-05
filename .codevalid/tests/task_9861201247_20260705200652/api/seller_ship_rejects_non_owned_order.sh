#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_ID="buyer-notowner-${CASE_SUFFIX}"
SELLER_USER_1_ID="seller-user-owner-${CASE_SUFFIX}"
SELLER_PROFILE_1_ID="seller-profile-owner-${CASE_SUFFIX}"
SELLER_USER_2_ID="seller-user-other-${CASE_SUFFIX}"
SELLER_PROFILE_2_ID="seller-profile-other-${CASE_SUFFIX}"
PRODUCT_ID="prod-notowner-${CASE_SUFFIX}"
ORDER_ID="order-notowner-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/seller_ship_rejects_non_owned_order_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/seller_ship_rejects_non_owned_order_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
OTHER_SELLER_TOKEN="$(node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1], email: 'seller+'+process.argv[2]+'@example.com', role: 'SELLER', status: 'ACTIVE', sellerProfileId: process.argv[3]}, 'dev-secret', {expiresIn:'7d'}));" "$SELLER_USER_2_ID" "$CASE_SUFFIX" "$SELLER_PROFILE_2_ID")"
psql "$DATABASE_URL" <<SQL
INSERT INTO "User" (id, email, password, role, status, "createdAt") VALUES
  ('${BUYER_ID}', 'buyer+${CASE_SUFFIX}@example.com', 'pw', 'BUYER', 'ACTIVE', NOW()),
  ('${SELLER_USER_1_ID}', 'seller1+${CASE_SUFFIX}@example.com', 'pw', 'SELLER', 'ACTIVE', NOW()),
  ('${SELLER_USER_2_ID}', 'seller2+${CASE_SUFFIX}@example.com', 'pw', 'SELLER', 'ACTIVE', NOW());
INSERT INTO "SellerProfile" (id, "userId", "storeName", bio, status, "createdAt") VALUES
  ('${SELLER_PROFILE_1_ID}', '${SELLER_USER_1_ID}', 'Owner Store ${CASE_SUFFIX}', 'bio', 'ACTIVE', NOW()),
  ('${SELLER_PROFILE_2_ID}', '${SELLER_USER_2_ID}', 'Other Store ${CASE_SUFFIX}', 'bio', 'ACTIVE', NOW());
INSERT INTO "Product" (id, title, description, price_cents, stock_qty, visible, status, "sellerId", category, "createdAt") VALUES
  ('${PRODUCT_ID}', 'Owner Product ${CASE_SUFFIX}', 'desc', 1999, 8, true, 'ACTIVE', '${SELLER_PROFILE_1_ID}', 'general', NOW());
INSERT INTO "Order" (id, buyer_id, total_cents, platform_fee_cents, status, "createdAt") VALUES
  ('${ORDER_ID}', '${BUYER_ID}', 1999, 200, 'PAID', NOW());
INSERT INTO "OrderItem" (id, "orderId", "productId", "sellerId", qty, price_at_purchase, seller_payout_cents) VALUES
  ('oi-notowner-${CASE_SUFFIX}', '${ORDER_ID}', '${PRODUCT_ID}', '${SELLER_PROFILE_1_ID}', 1, 1999, 1799);
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/orders/${ORDER_ID}/ship" \
  -H "Authorization: Bearer ${OTHER_SELLER_TOKEN}" \
  -H 'Content-Type: application/json' > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "403" ]
grep -F 'No items for your shop in this order' "$RESPONSE_FILE" >/dev/null
DB_STATUS="$(psql "$DATABASE_URL" -At -c "SELECT status FROM \"Order\" WHERE id = '${ORDER_ID}';")"
[ "$DB_STATUS" = 'PAID' ]
echo 'CODEVALID_TEST_ASSERTION_OK:seller_ship_rejects_non_owned_order'

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM "OrderItem" WHERE "orderId" = '${ORDER_ID}';
DELETE FROM "Order" WHERE id = '${ORDER_ID}';
DELETE FROM "Product" WHERE id = '${PRODUCT_ID}';
DELETE FROM "SellerProfile" WHERE id IN ('${SELLER_PROFILE_1_ID}', '${SELLER_PROFILE_2_ID}');
DELETE FROM "User" WHERE id IN ('${BUYER_ID}', '${SELLER_USER_1_ID}', '${SELLER_USER_2_ID}');
SQL
