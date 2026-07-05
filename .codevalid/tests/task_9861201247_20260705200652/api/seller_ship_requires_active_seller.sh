#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_ID="buyer-shipforbid-${CASE_SUFFIX}"
SELLER_USER_ID="seller-user-shipforbid-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-shipforbid-${CASE_SUFFIX}"
PRODUCT_ID="prod-shipforbid-${CASE_SUFFIX}"
ORDER_ID="order-shipforbid-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/seller_ship_requires_active_seller_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/seller_ship_requires_active_seller_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
INACTIVE_SELLER_TOKEN="$(node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1], email: 'seller+'+process.argv[2]+'@example.com', role: 'SELLER', status: 'PENDING', sellerProfileId: process.argv[3]}, 'dev-secret', {expiresIn:'7d'}));" "$SELLER_USER_ID" "$CASE_SUFFIX" "$SELLER_PROFILE_ID")"
psql "$DATABASE_URL" <<SQL
INSERT INTO "User" (id, email, password, role, status, "createdAt") VALUES
  ('${BUYER_ID}', 'buyer+${CASE_SUFFIX}@example.com', 'pw', 'BUYER', 'ACTIVE', NOW()),
  ('${SELLER_USER_ID}', 'seller+${CASE_SUFFIX}@example.com', 'pw', 'SELLER', 'PENDING', NOW());
INSERT INTO "SellerProfile" (id, "userId", "storeName", bio, status, "createdAt") VALUES
  ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Pending Ship Store ${CASE_SUFFIX}', 'bio', 'PENDING', NOW());
INSERT INTO "Product" (id, title, description, price_cents, stock_qty, visible, status, "sellerId", category, "createdAt") VALUES
  ('${PRODUCT_ID}', 'Pending Ship Product ${CASE_SUFFIX}', 'desc', 1999, 8, true, 'ACTIVE', '${SELLER_PROFILE_ID}', 'general', NOW());
INSERT INTO "Order" (id, buyer_id, total_cents, platform_fee_cents, status, "createdAt") VALUES
  ('${ORDER_ID}', '${BUYER_ID}', 1999, 200, 'PAID', NOW());
INSERT INTO "OrderItem" (id, "orderId", "productId", "sellerId", qty, price_at_purchase, seller_payout_cents) VALUES
  ('oi-shipforbid-${CASE_SUFFIX}', '${ORDER_ID}', '${PRODUCT_ID}', '${SELLER_PROFILE_ID}', 1, 1999, 1799);
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
echo 'CODEVALID_TEST_ASSERTION_OK:seller_ship_requires_active_seller'

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM "OrderItem" WHERE "orderId" = '${ORDER_ID}';
DELETE FROM "Order" WHERE id = '${ORDER_ID}';
DELETE FROM "Product" WHERE id = '${PRODUCT_ID}';
DELETE FROM "SellerProfile" WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM "User" WHERE id IN ('${BUYER_ID}', '${SELLER_USER_ID}');
SQL
