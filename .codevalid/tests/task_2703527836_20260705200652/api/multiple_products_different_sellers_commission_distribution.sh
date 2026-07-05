#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_ID="buyer-multi-${CASE_SUFFIX}"
SELLER_USER_A="seller-user-a-${CASE_SUFFIX}"
SELLER_PROFILE_A="seller-profile-a-${CASE_SUFFIX}"
SELLER_USER_B="seller-user-b-${CASE_SUFFIX}"
SELLER_PROFILE_B="seller-profile-b-${CASE_SUFFIX}"
SELLER_USER_C="seller-user-c-${CASE_SUFFIX}"
SELLER_PROFILE_C="seller-profile-c-${CASE_SUFFIX}"
PROD_A="prod-a-${CASE_SUFFIX}"
PROD_B="prod-b-${CASE_SUFFIX}"
PROD_C="prod-c-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/multiple_products_different_sellers_commission_distribution_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/multiple_products_different_sellers_commission_distribution_${CASE_SUFFIX}.status"
trap 'rm -f "$RESPONSE_FILE" "$STATUS_FILE"' EXIT
ORDER_ID=""

# Given
BUYER_TOKEN="$(node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1], email: 'buyer+'+process.argv[1]+'@example.com', role: 'BUYER', status: 'ACTIVE'}, 'dev-secret', {expiresIn:'7d'}));" "$BUYER_ID")"
psql "$DATABASE_URL" <<SQL
INSERT INTO "User" (id, email, password, role, status, "createdAt") VALUES
  ('${BUYER_ID}', 'buyer+${CASE_SUFFIX}@example.com', 'pw', 'BUYER', 'ACTIVE', NOW()),
  ('${SELLER_USER_A}', 'sellera+${CASE_SUFFIX}@example.com', 'pw', 'SELLER', 'ACTIVE', NOW()),
  ('${SELLER_USER_B}', 'sellerb+${CASE_SUFFIX}@example.com', 'pw', 'SELLER', 'ACTIVE', NOW()),
  ('${SELLER_USER_C}', 'sellerc+${CASE_SUFFIX}@example.com', 'pw', 'SELLER', 'ACTIVE', NOW());
INSERT INTO "SellerProfile" (id, "userId", "storeName", bio, status, "createdAt") VALUES
  ('${SELLER_PROFILE_A}', '${SELLER_USER_A}', 'Store A ${CASE_SUFFIX}', 'bio', 'ACTIVE', NOW()),
  ('${SELLER_PROFILE_B}', '${SELLER_USER_B}', 'Store B ${CASE_SUFFIX}', 'bio', 'ACTIVE', NOW()),
  ('${SELLER_PROFILE_C}', '${SELLER_USER_C}', 'Store C ${CASE_SUFFIX}', 'bio', 'ACTIVE', NOW());
INSERT INTO "Product" (id, title, description, price_cents, stock_qty, visible, status, "sellerId", category, "createdAt") VALUES
  ('${PROD_A}', 'Product A ${CASE_SUFFIX}', 'desc', 1000, 10, true, 'ACTIVE', '${SELLER_PROFILE_A}', 'general', NOW()),
  ('${PROD_B}', 'Product B ${CASE_SUFFIX}', 'desc', 2000, 10, true, 'ACTIVE', '${SELLER_PROFILE_B}', 'general', NOW()),
  ('${PROD_C}', 'Product C ${CASE_SUFFIX}', 'desc', 3000, 10, true, 'ACTIVE', '${SELLER_PROFILE_C}', 'general', NOW());
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/orders/checkout" \
  -H "Authorization: Bearer ${BUYER_TOKEN}" \
  -H 'Content-Type: application/json' \
  --data "{\"items\":[{\"product_id\":\"${PROD_A}\",\"qty\":1},{\"product_id\":\"${PROD_B}\",\"qty\":2},{\"product_id\":\"${PROD_C}\",\"qty\":1}]}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
ORDER_ID="$(sed -n 's/.*"order_id":"\([^"]*\)".*/\1/p' "$RESPONSE_FILE")"
[ -n "$ORDER_ID" ]
ORDER_CHECK="$(psql "$DATABASE_URL" -At -F '|' -c "SELECT total_cents, platform_fee_cents, status FROM \"Order\" WHERE id = '${ORDER_ID}';")"
[ "$ORDER_CHECK" = '8000|800|PAID' ]
ITEM_A="$(psql "$DATABASE_URL" -At -c "SELECT seller_payout_cents FROM \"OrderItem\" WHERE \"orderId\" = '${ORDER_ID}' AND \"productId\" = '${PROD_A}';")"
[ "$ITEM_A" = '900' ]
ITEM_B="$(psql "$DATABASE_URL" -At -c "SELECT seller_payout_cents FROM \"OrderItem\" WHERE \"orderId\" = '${ORDER_ID}' AND \"productId\" = '${PROD_B}';")"
[ "$ITEM_B" = '3600' ]
ITEM_C="$(psql "$DATABASE_URL" -At -c "SELECT seller_payout_cents FROM \"OrderItem\" WHERE \"orderId\" = '${ORDER_ID}' AND \"productId\" = '${PROD_C}';")"
[ "$ITEM_C" = '2700' ]
echo 'CODEVALID_TEST_ASSERTION_OK:multiple_products_different_sellers_commission_distribution'

# Cleanup
if [ -n "$ORDER_ID" ]; then
psql "$DATABASE_URL" <<SQL
DELETE FROM "OrderItem" WHERE "orderId" = '${ORDER_ID}';
DELETE FROM "Order" WHERE id = '${ORDER_ID}';
SQL
fi
psql "$DATABASE_URL" <<SQL
DELETE FROM "Product" WHERE id IN ('${PROD_A}', '${PROD_B}', '${PROD_C}');
DELETE FROM "SellerProfile" WHERE id IN ('${SELLER_PROFILE_A}', '${SELLER_PROFILE_B}', '${SELLER_PROFILE_C}');
DELETE FROM "User" WHERE id IN ('${BUYER_ID}', '${SELLER_USER_A}', '${SELLER_USER_B}', '${SELLER_USER_C}');
SQL
