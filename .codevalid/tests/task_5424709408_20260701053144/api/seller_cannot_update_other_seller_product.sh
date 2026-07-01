#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_A_USER_ID="seller-a-${CASE_SUFFIX}"
SELLER_A_ID="profile-a-${CASE_SUFFIX}"
SELLER_A_EMAIL="seller-a-${CASE_SUFFIX}@example.com"
SELLER_B_USER_ID="seller-b-${CASE_SUFFIX}"
SELLER_B_ID="profile-b-${CASE_SUFFIX}"
SELLER_B_EMAIL="seller-b-${CASE_SUFFIX}@example.com"
PRODUCT_ID="prod-b-${CASE_SUFFIX}"
TOKEN_FILE="/tmp/seller_cannot_update_other_seller_product_${CASE_SUFFIX}.token"
RESPONSE_FILE="/tmp/seller_cannot_update_other_seller_product_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/seller_cannot_update_other_seller_product_${CASE_SUFFIX}.status"
cleanup() {
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id='${PRODUCT_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id IN ('${SELLER_A_ID}','${SELLER_B_ID}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id IN ('${SELLER_A_USER_ID}','${SELLER_B_USER_ID}');" >/dev/null 2>&1 || true
  rm -f "$TOKEN_FILE" "$RESPONSE_FILE" "$STATUS_FILE"
}
trap cleanup EXIT

# Given
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('${SELLER_A_USER_ID}', '${SELLER_A_EMAIL}', 'hash', 'SELLER', 'ACTIVE');"
psql "$DATABASE_URL" -c "INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('${SELLER_A_ID}', '${SELLER_A_USER_ID}', 'Seller A Store ${CASE_SUFFIX}', 'Seller A bio ${CASE_SUFFIX}');"
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('${SELLER_B_USER_ID}', '${SELLER_B_EMAIL}', 'hash', 'SELLER', 'ACTIVE');"
psql "$DATABASE_URL" -c "INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('${SELLER_B_ID}', '${SELLER_B_USER_ID}', 'Seller B Store ${CASE_SUFFIX}', 'Seller B bio ${CASE_SUFFIX}');"
psql "$DATABASE_URL" -c "INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible) VALUES ('${PRODUCT_ID}', '${SELLER_B_ID}', 'Seller B Original', 'Protected description', 'HOME_GOODS', 3400, 7, '[\"https://example.com/other-seller.jpg\"]', 'ACTIVE', true);"
node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"SELLER",status:"ACTIVE"}, process.env.JWT_SECRET));' "$SELLER_A_USER_ID" "$SELLER_A_EMAIL" > "$TOKEN_FILE"
TOKEN="$(cat "$TOKEN_FILE")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X PUT "$BASE_URL/products/${PRODUCT_ID}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  --data '{"title":"Unauthorized Update"}' > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "404" ]
grep -F '"error":"Product not found"' "$RESPONSE_FILE" >/dev/null
DB_TITLE="$(psql "$DATABASE_URL" -t -A -c "SELECT title FROM products WHERE id='${PRODUCT_ID}' AND seller_id='${SELLER_B_ID}';")"
[ "$DB_TITLE" = 'Seller B Original' ]
echo "CODEVALID_TEST_ASSERTION_OK:seller_cannot_update_other_seller_product"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM products WHERE id='${PRODUCT_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id IN ('${SELLER_A_ID}','${SELLER_B_ID}');" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM users WHERE id IN ('${SELLER_A_USER_ID}','${SELLER_B_USER_ID}');" >/dev/null 2>&1 || true
