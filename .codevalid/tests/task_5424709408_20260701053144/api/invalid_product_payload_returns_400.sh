#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
USER_ID="user-invalid-${CASE_SUFFIX}"
SELLER_ID="seller-profile-invalid-${CASE_SUFFIX}"
EMAIL="invalid-${CASE_SUFFIX}@example.com"
TOKEN_FILE="/tmp/invalid_product_payload_returns_400_${CASE_SUFFIX}.token"
RESPONSE_FILE="/tmp/invalid_product_payload_returns_400_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/invalid_product_payload_returns_400_${CASE_SUFFIX}.status"
cleanup() {
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE seller_id='${SELLER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
  rm -f "$TOKEN_FILE" "$RESPONSE_FILE" "$STATUS_FILE"
}
trap cleanup EXIT

# Given
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('${USER_ID}', '${EMAIL}', 'hash', 'SELLER', 'ACTIVE');"
psql "$DATABASE_URL" -c "INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('${SELLER_ID}', '${USER_ID}', 'Invalid Payload Store ${CASE_SUFFIX}', 'Bio ${CASE_SUFFIX}');"
node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"SELLER",status:"ACTIVE"}, process.env.JWT_SECRET));' "$USER_ID" "$EMAIL" > "$TOKEN_FILE"
TOKEN="$(cat "$TOKEN_FILE")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  --data '{"description":"Bad data","category":"HOME_GOODS","price_cents":"free","stock_qty":5,"photos":[]}' > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "400" ]
grep -F '"error":' "$RESPONSE_FILE" >/dev/null
DB_COUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM products WHERE seller_id='${SELLER_ID}';")"
[ "$DB_COUNT" = "0" ]
echo "CODEVALID_TEST_ASSERTION_OK:invalid_product_payload_returns_400"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
