#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="earnings_calculation_correct"
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
  psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE id LIKE 'earn_oi_${CASE_SUFFIX}_%';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM orders WHERE id LIKE 'earn_ord_${CASE_SUFFIX}_%';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id='${PRODUCT_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id IN ('${USER_ID}','${BUYER_ID}');" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('${USER_ID}', '${USER_EMAIL}', 'hash', 'SELLER', 'ACTIVE');" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('${SELLER_ID}', '${USER_ID}', 'Math Store', 'sum check');" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible) VALUES ('${PRODUCT_ID}', '${SELLER_ID}', 'Calculator Widget', 'math item', 'OFFICE', 3000, 10, '[]'::jsonb, 'ACTIVE', true);" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('${BUYER_ID}', '${BUYER_EMAIL}', 'hash', 'BUYER', 'ACTIVE');" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO orders (id, buyer_id, status) VALUES ('earn_ord_${CASE_SUFFIX}_1', '${BUYER_ID}', 'PAID');" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO orders (id, buyer_id, status) VALUES ('earn_ord_${CASE_SUFFIX}_2', '${BUYER_ID}', 'PAID');" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO orders (id, buyer_id, status) VALUES ('earn_ord_${CASE_SUFFIX}_3', '${BUYER_ID}', 'PAID');" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO order_items (id, order_id, product_id, qty, price_cents, seller_payout_cents) VALUES ('earn_oi_${CASE_SUFFIX}_1', 'earn_ord_${CASE_SUFFIX}_1', '${PRODUCT_ID}', 1, 3000, 1000);" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO order_items (id, order_id, product_id, qty, price_cents, seller_payout_cents) VALUES ('earn_oi_${CASE_SUFFIX}_2', 'earn_ord_${CASE_SUFFIX}_2', '${PRODUCT_ID}', 1, 3000, 2500);" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO order_items (id, order_id, product_id, qty, price_cents, seller_payout_cents) VALUES ('earn_oi_${CASE_SUFFIX}_3', 'earn_ord_${CASE_SUFFIX}_3', '${PRODUCT_ID}', 1, 3000, 500);" >/dev/null
node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"SELLER",status:"ACTIVE",sellerProfileId:process.argv[3]}, process.env.JWT_SECRET));' "$USER_ID" "$USER_EMAIL" "$SELLER_ID" > "$TOKEN_FILE"
TOKEN="$(cat "$TOKEN_FILE")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X GET "$BASE_URL/seller/dashboard" \
  -H "Authorization: Bearer ${TOKEN}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
grep -F '"total_earnings_cents":4000' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:earnings_calculation_correct"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM order_items WHERE id LIKE 'earn_oi_${CASE_SUFFIX}_%';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM orders WHERE id LIKE 'earn_ord_${CASE_SUFFIX}_%';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM products WHERE id='${PRODUCT_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM users WHERE id IN ('${USER_ID}','${BUYER_ID}');" >/dev/null 2>&1 || true
