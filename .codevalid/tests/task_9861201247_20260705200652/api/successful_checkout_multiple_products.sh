#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_ID="buyer-multi-${CASE_SUFFIX}"
SELLER_USER_1_ID="seller-user-a-${CASE_SUFFIX}"
SELLER_PROFILE_1_ID="seller-profile-a-${CASE_SUFFIX}"
SELLER_USER_2_ID="seller-user-b-${CASE_SUFFIX}"
SELLER_PROFILE_2_ID="seller-profile-b-${CASE_SUFFIX}"
PRODUCT_1_ID="prod-001-${CASE_SUFFIX}"
PRODUCT_2_ID="prod-002-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/successful_checkout_multiple_products_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/successful_checkout_multiple_products_${CASE_SUFFIX}.status"
ORDER_ID=""
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
BUYER_TOKEN="$(node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1], email: 'buyer+'+process.argv[2]+'@example.com', role: 'BUYER', status: 'ACTIVE'}, 'dev-secret', {expiresIn:'7d'}));" "$BUYER_ID" "$CASE_SUFFIX")"
psql "$DATABASE_URL" <<SQL
INSERT INTO "User" (id, email, password, role, status, "createdAt") VALUES
  ('${BUYER_ID}', 'buyer+${CASE_SUFFIX}@example.com', 'pw', 'BUYER', 'ACTIVE', NOW()),
  ('${SELLER_USER_1_ID}', 'sellerA+${CASE_SUFFIX}@example.com', 'pw', 'SELLER', 'ACTIVE', NOW()),
  ('${SELLER_USER_2_ID}', 'sellerB+${CASE_SUFFIX}@example.com', 'pw', 'SELLER', 'ACTIVE', NOW());
INSERT INTO "SellerProfile" (id, "userId", "storeName", bio, status, "createdAt") VALUES
  ('${SELLER_PROFILE_1_ID}', '${SELLER_USER_1_ID}', 'Store A ${CASE_SUFFIX}', 'bio', 'ACTIVE', NOW()),
  ('${SELLER_PROFILE_2_ID}', '${SELLER_USER_2_ID}', 'Store B ${CASE_SUFFIX}', 'bio', 'ACTIVE', NOW());
INSERT INTO "Product" (id, title, description, price_cents, stock_qty, visible, status, "sellerId", category, "createdAt") VALUES
  ('${PRODUCT_1_ID}', 'Product A ${CASE_SUFFIX}', 'desc', 1000, 5, true, 'ACTIVE', '${SELLER_PROFILE_1_ID}', 'general', NOW()),
  ('${PRODUCT_2_ID}', 'Product B ${CASE_SUFFIX}', 'desc', 2500, 10, true, 'ACTIVE', '${SELLER_PROFILE_2_ID}', 'general', NOW());
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/orders/checkout" \
  -H "Authorization: Bearer ${BUYER_TOKEN}" \
  -H 'Content-Type: application/json' \
  --data "{\"items\":[{\"product_id\":\"${PRODUCT_1_ID}\",\"qty\":1},{\"product_id\":\"${PRODUCT_2_ID}\",\"qty\":2}]}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
grep -F '"message":"Order placed"' "$RESPONSE_FILE" >/dev/null
ORDER_ID="$(sed -n 's/.*"order_id":"\([^"]*\)".*/\1/p' "$RESPONSE_FILE")"
[ -n "$ORDER_ID" ]
ORDER_ROW="$(psql "$DATABASE_URL" -At -F '|' -c "SELECT total_cents, status FROM \"Order\" WHERE id = '${ORDER_ID}';")"
[ "$ORDER_ROW" = '6000|PAID' ]
STOCK_1="$(psql "$DATABASE_URL" -At -c "SELECT stock_qty FROM \"Product\" WHERE id = '${PRODUCT_1_ID}';")"
[ "$STOCK_1" = '4' ]
STOCK_2="$(psql "$DATABASE_URL" -At -c "SELECT stock_qty FROM \"Product\" WHERE id = '${PRODUCT_2_ID}';")"
[ "$STOCK_2" = '8' ]
SELLER_COUNT="$(psql "$DATABASE_URL" -At -c "SELECT COUNT(DISTINCT \"sellerId\") FROM \"OrderItem\" WHERE \"orderId\" = '${ORDER_ID}';")"
[ "$SELLER_COUNT" = '2' ]
echo 'CODEVALID_TEST_ASSERTION_OK:successful_checkout_multiple_products'

# Cleanup
if [ -n "$ORDER_ID" ]; then
psql "$DATABASE_URL" <<SQL
DELETE FROM "OrderItem" WHERE "orderId" = '${ORDER_ID}';
DELETE FROM "Order" WHERE id = '${ORDER_ID}';
SQL
fi
psql "$DATABASE_URL" <<SQL
DELETE FROM "Product" WHERE id IN ('${PRODUCT_1_ID}', '${PRODUCT_2_ID}');
DELETE FROM "SellerProfile" WHERE id IN ('${SELLER_PROFILE_1_ID}', '${SELLER_PROFILE_2_ID}');
DELETE FROM "User" WHERE id IN ('${BUYER_ID}', '${SELLER_USER_1_ID}', '${SELLER_USER_2_ID}');
SQL
