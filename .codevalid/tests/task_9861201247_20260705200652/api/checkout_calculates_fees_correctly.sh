#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_ID="buyer-fees-${CASE_SUFFIX}"
SELLER_USER_ID="seller-user-fees-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-fees-${CASE_SUFFIX}"
PRODUCT_ID="prod-fees-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/checkout_calculates_fees_correctly_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/checkout_calculates_fees_correctly_${CASE_SUFFIX}.status"
ORDER_ID=""
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
BUYER_TOKEN="$(node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1], email: 'buyer+'+process.argv[2]+'@example.com', role: 'BUYER', status: 'ACTIVE'}, 'dev-secret', {expiresIn:'7d'}));" "$BUYER_ID" "$CASE_SUFFIX")"
psql "$DATABASE_URL" <<SQL
INSERT INTO "User" (id, email, password, role, status, "createdAt") VALUES
  ('${BUYER_ID}', 'buyer+${CASE_SUFFIX}@example.com', 'pw', 'BUYER', 'ACTIVE', NOW()),
  ('${SELLER_USER_ID}', 'seller+${CASE_SUFFIX}@example.com', 'pw', 'SELLER', 'ACTIVE', NOW());
INSERT INTO "SellerProfile" (id, "userId", "storeName", bio, status, "createdAt") VALUES
  ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Fees Store ${CASE_SUFFIX}', 'bio', 'ACTIVE', NOW());
INSERT INTO "Product" (id, title, description, price_cents, stock_qty, visible, status, "sellerId", category, "createdAt") VALUES
  ('${PRODUCT_ID}', 'Fees Product ${CASE_SUFFIX}', 'desc', 2000, 10, true, 'ACTIVE', '${SELLER_PROFILE_ID}', 'general', NOW());
SQL
EXPECTED_PLATFORM_FEE='200'
EXPECTED_SELLER_PAYOUT='1800'

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/orders/checkout" \
  -H "Authorization: Bearer ${BUYER_TOKEN}" \
  -H 'Content-Type: application/json' \
  --data "{\"items\":[{\"product_id\":\"${PRODUCT_ID}\",\"qty\":1}]}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
ORDER_ID="$(sed -n 's/.*"order_id":"\([^"]*\)".*/\1/p' "$RESPONSE_FILE")"
[ -n "$ORDER_ID" ]
ORDER_ROW="$(psql "$DATABASE_URL" -At -F '|' -c "SELECT total_cents, platform_fee_cents, status FROM \"Order\" WHERE id = '${ORDER_ID}';")"
[ "$ORDER_ROW" = "2000|${EXPECTED_PLATFORM_FEE}|PAID" ]
ITEM_ROW="$(psql "$DATABASE_URL" -At -F '|' -c "SELECT seller_payout_cents, qty, price_at_purchase FROM \"OrderItem\" WHERE \"orderId\" = '${ORDER_ID}' AND \"productId\" = '${PRODUCT_ID}';")"
[ "$ITEM_ROW" = "${EXPECTED_SELLER_PAYOUT}|1|2000" ]
echo 'CODEVALID_TEST_ASSERTION_OK:checkout_calculates_fees_correctly'

# Cleanup
if [ -n "$ORDER_ID" ]; then
psql "$DATABASE_URL" <<SQL
DELETE FROM "OrderItem" WHERE "orderId" = '${ORDER_ID}';
DELETE FROM "Order" WHERE id = '${ORDER_ID}';
SQL
fi
psql "$DATABASE_URL" <<SQL
DELETE FROM "Product" WHERE id = '${PRODUCT_ID}';
DELETE FROM "SellerProfile" WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM "User" WHERE id IN ('${BUYER_ID}', '${SELLER_USER_ID}');
SQL
