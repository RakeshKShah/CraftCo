#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="order_items_limited_to_50"
USER_ID="user_${TEST_ID}_${CASE_SUFFIX}"
SELLER_ID="seller_${TEST_ID}_${CASE_SUFFIX}"
PRODUCT_ID="prod_${TEST_ID}_${CASE_SUFFIX}"
BUYER_ID="buyer_${TEST_ID}_${CASE_SUFFIX}"
USER_EMAIL="${TEST_ID}-${CASE_SUFFIX}@example.com"
BUYER_EMAIL="buyer-${TEST_ID}-${CASE_SUFFIX}@example.com"
TOKEN_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.token"
RESPONSE_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.status"
cleanup_files() {
  rm -f "$TOKEN_FILE" "$RESPONSE_FILE" "$STATUS_FILE"
}
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE id LIKE 'oi_${CASE_SUFFIX}_%';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM orders WHERE id LIKE 'ord_${CASE_SUFFIX}_%';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id='${PRODUCT_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id IN ('${USER_ID}','${BUYER_ID}');" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('${USER_ID}', '${USER_EMAIL}', 'hash', 'SELLER', 'ACTIVE');" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('${SELLER_ID}', '${USER_ID}', 'Busy Store', 'many orders');" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible) VALUES ('${PRODUCT_ID}', '${SELLER_ID}', 'Popular Item', 'high volume product', 'TECH', 9900, 100, '[]'::jsonb, 'ACTIVE', true);" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('${BUYER_ID}', '${BUYER_EMAIL}', 'hash', 'BUYER', 'ACTIVE');" >/dev/null
i=1
while [ "$i" -le 60 ]; do
  ORDER_ID="ord_${CASE_SUFFIX}_${i}"
  ORDER_ITEM_ID="oi_${CASE_SUFFIX}_${i}"
  psql "$DATABASE_URL" -c "INSERT INTO orders (id, buyer_id, status, created_at) VALUES ('${ORDER_ID}', '${BUYER_ID}', 'PAID', NOW() + (${i} || ' seconds')::interval);" >/dev/null
  psql "$DATABASE_URL" -c "INSERT INTO order_items (id, order_id, product_id, qty, price_cents, seller_payout_cents) VALUES ('${ORDER_ITEM_ID}', '${ORDER_ID}', '${PRODUCT_ID}', 1, 9900, 500);" >/dev/null
  i=$((i + 1))
done
node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"SELLER",status:"ACTIVE",sellerProfileId:process.argv[3]}, process.env.JWT_SECRET));' "$USER_ID" "$USER_EMAIL" "$SELLER_ID" > "$TOKEN_FILE"
TOKEN="$(cat "$TOKEN_FILE")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X GET "$BASE_URL/seller/dashboard" \
  -H "Authorization: Bearer ${TOKEN}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
ORDER_COUNT="$(jq '.orders | length' "$RESPONSE_FILE")"
[ "$ORDER_COUNT" = "50" ]
FIRST_CREATED_AT="$(jq -r '.orders[0].created_at' "$RESPONSE_FILE")"
LAST_CREATED_AT="$(jq -r '.orders[49].created_at' "$RESPONSE_FILE")"
[ "$FIRST_CREATED_AT" != "null" ]
[ "$LAST_CREATED_AT" != "null" ]
if command -v date >/dev/null 2>&1; then
  FIRST_EPOCH="$(date -u -d "$FIRST_CREATED_AT" +%s)"
  LAST_EPOCH="$(date -u -d "$LAST_CREATED_AT" +%s)"
  [ "$FIRST_EPOCH" -ge "$LAST_EPOCH" ]
fi

echo "CODEVALID_TEST_ASSERTION_OK:order_items_limited_to_50"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE id LIKE 'oi_${CASE_SUFFIX}_%';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM orders WHERE id LIKE 'ord_${CASE_SUFFIX}_%';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM products WHERE id='${PRODUCT_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM users WHERE id IN ('${USER_ID}','${BUYER_ID}');" >/dev/null 2>&1 || true
