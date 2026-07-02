#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
USER_ID="user-suspended-${CASE_SUFFIX}"
SELLER_ID="seller-suspended-${CASE_SUFFIX}"
EMAIL="suspended-${CASE_SUFFIX}@example.com"
TITLE="Banned Item ${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/suspended_seller_cannot_create_product_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/suspended_seller_cannot_create_product_${CASE_SUFFIX}.status"
TOKEN_FILE="/tmp/suspended_seller_cannot_create_product_${CASE_SUFFIX}.token"
cleanup() {
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE seller_id='${SELLER_ID}' AND title='${TITLE}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE" "$STATUS_FILE" "$TOKEN_FILE"
}
trap cleanup EXIT

# Given
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('${USER_ID}', '${EMAIL}', 'hash', 'SELLER', 'SUSPENDED');"
psql "$DATABASE_URL" -c "INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('${SELLER_ID}', '${USER_ID}', 'Suspended Store ${CASE_SUFFIX}', 'Restricted seller');"
node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"SELLER",status:"SUSPENDED",sellerProfileId:process.argv[3]}, process.env.JWT_SECRET));' "$USER_ID" "$EMAIL" "$SELLER_ID" > "$TOKEN_FILE"
TOKEN="$(cat "$TOKEN_FILE")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  --data "{\"title\":\"${TITLE}\",\"description\":\"Blocked item\",\"category\":\"OTHER\",\"price_cents\":1000,\"stock_qty\":1,\"photos\":[\"https://example.com/blocked.jpg\"]}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "403" ]
grep -F '"error":"Suspended sellers cannot create products"' "$RESPONSE_FILE" >/dev/null
DB_COUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM products WHERE seller_id='${SELLER_ID}' AND title='${TITLE}';")"
[ "$DB_COUNT" = "0" ]
echo "CODEVALID_TEST_ASSERTION_OK:suspended_seller_cannot_create_product"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
