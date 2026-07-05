#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-user-role-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-role-${CASE_SUFFIX}"
PRODUCT_ID="prod-role-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/checkout_requires_buyer_role_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/checkout_requires_buyer_role_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
SELLER_TOKEN="$(node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1], email: 'seller+'+process.argv[2]+'@example.com', role: 'SELLER', status: 'ACTIVE', sellerProfileId: process.argv[3]}, 'dev-secret', {expiresIn:'7d'}));" "$SELLER_USER_ID" "$CASE_SUFFIX" "$SELLER_PROFILE_ID")"
psql "$DATABASE_URL" <<SQL
INSERT INTO "User" (id, email, password, role, status, "createdAt") VALUES
  ('${SELLER_USER_ID}', 'seller+${CASE_SUFFIX}@example.com', 'pw', 'SELLER', 'ACTIVE', NOW());
INSERT INTO "SellerProfile" (id, "userId", "storeName", bio, status, "createdAt") VALUES
  ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Seller Role Store ${CASE_SUFFIX}', 'bio', 'ACTIVE', NOW());
INSERT INTO "Product" (id, title, description, price_cents, stock_qty, visible, status, "sellerId", category, "createdAt") VALUES
  ('${PRODUCT_ID}', 'Seller Role Product ${CASE_SUFFIX}', 'desc', 1999, 10, true, 'ACTIVE', '${SELLER_PROFILE_ID}', 'general', NOW());
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/orders/checkout" \
  -H "Authorization: Bearer ${SELLER_TOKEN}" \
  -H 'Content-Type: application/json' \
  --data "{\"items\":[{\"product_id\":\"${PRODUCT_ID}\",\"qty\":1}]}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "403" ]
ORDER_COUNT="$(psql "$DATABASE_URL" -At -c "SELECT COUNT(*) FROM \"Order\" WHERE buyer_id = '${SELLER_USER_ID}';")"
[ "$ORDER_COUNT" = '0' ]
echo 'CODEVALID_TEST_ASSERTION_OK:checkout_requires_buyer_role'

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM "Product" WHERE id = '${PRODUCT_ID}';
DELETE FROM "SellerProfile" WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM "User" WHERE id = '${SELLER_USER_ID}';
SQL
