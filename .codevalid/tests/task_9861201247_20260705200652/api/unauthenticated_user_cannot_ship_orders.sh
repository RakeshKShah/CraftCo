#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_ID="buyer-unauth-ship-${CASE_SUFFIX}"
SELLER_USER_ID="seller-user-unauth-ship-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-unauth-ship-${CASE_SUFFIX}"
PRODUCT_ID="product-unauth-ship-${CASE_SUFFIX}"
ORDER_ID="order-unauth-ship-${CASE_SUFFIX}"
ORDER_ITEM_ID="order-item-unauth-ship-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/unauthenticated_user_cannot_ship_orders_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/unauthenticated_user_cannot_ship_orders_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL
DELETE FROM "OrderItem" WHERE id = '${ORDER_ITEM_ID}';
DELETE FROM "Order" WHERE id = '${ORDER_ID}';
DELETE FROM "Product" WHERE id = '${PRODUCT_ID}';
DELETE FROM "SellerProfile" WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM "User" WHERE id IN ('${BUYER_ID}', '${SELLER_USER_ID}');
INSERT INTO "User" (id, email, password, role, status, "createdAt") VALUES
  ('${BUYER_ID}', 'buyer.unauth.ship+${CASE_SUFFIX}@example.com', 'pw', 'BUYER', 'ACTIVE', NOW()),
  ('${SELLER_USER_ID}', 'seller.unauth.ship+${CASE_SUFFIX}@example.com', 'pw', 'SELLER', 'ACTIVE', NOW());
INSERT INTO "SellerProfile" (id, "userId", "storeName", bio, status, "createdAt") VALUES
  ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Unauth Ship Store ${CASE_SUFFIX}', 'bio', 'ACTIVE', NOW());
INSERT INTO "Product" (id, title, description, price_cents, stock_qty, visible, status, "sellerId", category, "createdAt") VALUES
  ('${PRODUCT_ID}', 'Unauth Ship Product ${CASE_SUFFIX}', 'desc', 2499, 7, true, 'ACTIVE', '${SELLER_PROFILE_ID}', 'general', NOW());
INSERT INTO "Order" (id, buyer_id, total_cents, platform_fee_cents, status, "createdAt") VALUES
  ('${ORDER_ID}', '${BUYER_ID}', 2499, 250, 'PAID', NOW());
INSERT INTO "OrderItem" (id, "orderId", "productId", "sellerId", qty, price_at_purchase, seller_payout_cents) VALUES
  ('${ORDER_ITEM_ID}', '${ORDER_ID}', '${PRODUCT_ID}', '${SELLER_PROFILE_ID}', 1, 2499, 2249);
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/orders/${ORDER_ID}/ship" \
  -H 'Content-Type: application/json' > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
case "$STATUS" in
  401|403) ;;
  *)
    echo "Expected 401 or 403 for unauthenticated request, got $STATUS" >&2
    exit 1
    ;;
esac
if [ "$STATUS" = "401" ]; then
  :
else
  grep -Ei 'unauth|unauthorized|auth|token|forbidden' "$RESPONSE_FILE" >/dev/null
fi
DB_STATUS="$(psql "$DATABASE_URL" -At -c "SELECT status FROM \"Order\" WHERE id = '${ORDER_ID}';")"
[ "$DB_STATUS" = 'PAID' ]
echo 'CODEVALID_TEST_ASSERTION_OK:unauthenticated_user_cannot_ship_orders'

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM "OrderItem" WHERE id = '${ORDER_ITEM_ID}';
DELETE FROM "Order" WHERE id = '${ORDER_ID}';
DELETE FROM "Product" WHERE id = '${PRODUCT_ID}';
DELETE FROM "SellerProfile" WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM "User" WHERE id IN ('${BUYER_ID}', '${SELLER_USER_ID}');
SQL
