#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-user-missing-order-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-missing-order-${CASE_SUFFIX}"
MISSING_ORDER_ID="order-missing-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/cannot_ship_non_existent_order_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/cannot_ship_non_existent_order_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
SELLER_TOKEN="$(node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1], email: 'seller.missing.order+'+process.argv[2]+'@example.com', role: 'SELLER', status: 'ACTIVE', sellerProfileId: process.argv[3]}, 'dev-secret', {expiresIn:'7d'}));" "$SELLER_USER_ID" "$CASE_SUFFIX" "$SELLER_PROFILE_ID")"
psql "$DATABASE_URL" <<SQL
DELETE FROM "SellerProfile" WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM "User" WHERE id = '${SELLER_USER_ID}';
INSERT INTO "User" (id, email, password, role, status, "createdAt") VALUES
  ('${SELLER_USER_ID}', 'seller.missing.order+${CASE_SUFFIX}@example.com', 'pw', 'SELLER', 'ACTIVE', NOW());
INSERT INTO "SellerProfile" (id, "userId", "storeName", bio, status, "createdAt") VALUES
  ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Missing Order Store ${CASE_SUFFIX}', 'bio', 'ACTIVE', NOW());
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/orders/${MISSING_ORDER_ID}/ship" \
  -H "Authorization: Bearer ${SELLER_TOKEN}" \
  -H 'Content-Type: application/json' > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "404" ]
grep -F 'Order not found' "$RESPONSE_FILE" >/dev/null
echo 'CODEVALID_TEST_ASSERTION_OK:cannot_ship_non_existent_order'

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM "SellerProfile" WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM "User" WHERE id = '${SELLER_USER_ID}';
SQL
