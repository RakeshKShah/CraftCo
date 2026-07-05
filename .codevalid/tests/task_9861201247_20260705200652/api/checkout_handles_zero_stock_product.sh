#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_ID="buyer-zerostock-${CASE_SUFFIX}"
SELLER_USER_ID="seller-user-zerostock-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-zerostock-${CASE_SUFFIX}"
PRODUCT_ID="prod-soldout-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/checkout_handles_zero_stock_product_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/checkout_handles_zero_stock_product_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
BUYER_TOKEN="$(node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1], email: 'buyer+'+process.argv[2]+'@example.com', role: 'BUYER', status: 'ACTIVE'}, 'dev-secret', {expiresIn:'7d'}));" "$BUYER_ID" "$CASE_SUFFIX")"
psql "$DATABASE_URL" <<SQL
INSERT INTO "User" (id, email, password, role, status, "createdAt") VALUES
  ('${BUYER_ID}', 'buyer+${CASE_SUFFIX}@example.com', 'pw', 'BUYER', 'ACTIVE', NOW()),
  ('${SELLER_USER_ID}', 'seller+${CASE_SUFFIX}@example.com', 'pw', 'SELLER', 'ACTIVE', NOW());
INSERT INTO "SellerProfile" (id, "userId", "storeName", bio, status, "createdAt") VALUES
  ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Zero Stock Store ${CASE_SUFFIX}', 'bio', 'ACTIVE', NOW());
INSERT INTO "Product" (id, title, description, price_cents, stock_qty, visible, status, "sellerId", category, "createdAt") VALUES
  ('${PRODUCT_ID}', 'Sold Out Product ${CASE_SUFFIX}', 'desc', 1999, 0, true, 'SOLD_OUT', '${SELLER_PROFILE_ID}', 'general', NOW());
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/orders/checkout" \
  -H "Authorization: Bearer ${BUYER_TOKEN}" \
  -H 'Content-Type: application/json' \
  --data "{\"items\":[{\"product_id\":\"${PRODUCT_ID}\",\"qty\":1}]}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "400" ]
grep -F "Product ${PRODUCT_ID} unavailable" "$RESPONSE_FILE" >/dev/null
ORDER_COUNT="$(psql "$DATABASE_URL" -At -c "SELECT COUNT(*) FROM \"Order\" WHERE buyer_id = '${BUYER_ID}';")"
[ "$ORDER_COUNT" = '0' ]
STOCK_NOW="$(psql "$DATABASE_URL" -At -c "SELECT stock_qty FROM \"Product\" WHERE id = '${PRODUCT_ID}';")"
[ "$STOCK_NOW" = '0' ]
echo 'CODEVALID_TEST_ASSERTION_OK:checkout_handles_zero_stock_product'

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM "Product" WHERE id = '${PRODUCT_ID}';
DELETE FROM "SellerProfile" WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM "User" WHERE id IN ('${BUYER_ID}', '${SELLER_USER_ID}');
SQL
