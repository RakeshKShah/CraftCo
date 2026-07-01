#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
OWNER_USER_ID="seller-owner-${CASE_SUFFIX}"
OWNER_SELLER_ID="profile-owner-${CASE_SUFFIX}"
BUYER_USER_ID="buyer-${CASE_SUFFIX}"
PRODUCT_ID="prod-buyer-forbidden-${CASE_SUFFIX}"
OWNER_EMAIL="seller-owner-${CASE_SUFFIX}@example.com"
BUYER_EMAIL="buyer-${CASE_SUFFIX}@example.com"
TOKEN_FILE="/tmp/non_seller_role_cannot_update_product_${CASE_SUFFIX}.token"
RESPONSE_FILE="/tmp/non_seller_role_cannot_update_product_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/non_seller_role_cannot_update_product_${CASE_SUFFIX}.status"
cleanup() {
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id='${PRODUCT_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${OWNER_SELLER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id IN ('${BUYER_USER_ID}','${OWNER_USER_ID}');" >/dev/null 2>&1 || true
  rm -f "$TOKEN_FILE" "$RESPONSE_FILE" "$STATUS_FILE"
}
trap cleanup EXIT

# Given
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('${OWNER_USER_ID}', '${OWNER_EMAIL}', 'hash', 'SELLER', 'ACTIVE');"
psql "$DATABASE_URL" -c "INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('${OWNER_SELLER_ID}', '${OWNER_USER_ID}', 'Owner Store ${CASE_SUFFIX}', 'Owner bio ${CASE_SUFFIX}');"
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('${BUYER_USER_ID}', '${BUYER_EMAIL}', 'hash', 'BUYER', 'ACTIVE');"
psql "$DATABASE_URL" -c "INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible) VALUES ('${PRODUCT_ID}', '${OWNER_SELLER_ID}', 'Buyer Forbidden Original', 'Original description', 'BOOKS', 999, 11, '[\"https://example.com/buyer.jpg\"]', 'ACTIVE', true);"
node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"BUYER",status:"ACTIVE"}, process.env.JWT_SECRET));' "$BUYER_USER_ID" "$BUYER_EMAIL" > "$TOKEN_FILE"
TOKEN="$(cat "$TOKEN_FILE")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X PUT "$BASE_URL/products/${PRODUCT_ID}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  --data '{"title":"Buyer Attempt"}' > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "403" ]
grep -F '"error":"Seller access required"' "$RESPONSE_FILE" >/dev/null
DB_TITLE="$(psql "$DATABASE_URL" -t -A -c "SELECT title FROM products WHERE id='${PRODUCT_ID}';")"
[ "$DB_TITLE" = 'Buyer Forbidden Original' ]
echo "CODEVALID_TEST_ASSERTION_OK:non_seller_role_cannot_update_product"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM products WHERE id='${PRODUCT_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${OWNER_SELLER_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM users WHERE id IN ('${BUYER_USER_ID}','${OWNER_USER_ID}');" >/dev/null 2>&1 || true
