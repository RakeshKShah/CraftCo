#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
USER_ID="user-db-failure-${CASE_SUFFIX}"
SELLER_ID="seller-db-failure-${CASE_SUFFIX}"
EMAIL="db-failure-${CASE_SUFFIX}@example.com"
TITLE="DB Failure ${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/database_write_failure_handled_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/database_write_failure_handled_${CASE_SUFFIX}.status"
TOKEN_FILE="/tmp/database_write_failure_handled_${CASE_SUFFIX}.token"
cleanup() {
  psql "$DATABASE_URL" -c "ALTER TABLE products DROP CONSTRAINT IF EXISTS codevalid_products_price_nonnegative;" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE seller_id='${SELLER_ID}' OR title='${TITLE}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE" "$STATUS_FILE" "$TOKEN_FILE"
}
trap cleanup EXIT

# Given
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('${USER_ID}', '${EMAIL}', 'hash', 'SELLER', 'ACTIVE');"
psql "$DATABASE_URL" -c "INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('${SELLER_ID}', '${USER_ID}', 'Failure Store ${CASE_SUFFIX}', 'Constraint failure test');"
psql "$DATABASE_URL" -c "ALTER TABLE products DROP CONSTRAINT IF EXISTS codevalid_products_price_nonnegative;"
psql "$DATABASE_URL" -c "ALTER TABLE products ADD CONSTRAINT codevalid_products_price_nonnegative CHECK (price_cents >= 0);"
node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"SELLER",status:"ACTIVE",sellerProfileId:process.argv[3]}, process.env.JWT_SECRET));' "$USER_ID" "$EMAIL" "$SELLER_ID" > "$TOKEN_FILE"
TOKEN="$(cat "$TOKEN_FILE")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  --data "{\"title\":\"${TITLE}\",\"description\":\"Forces database failure\",\"category\":\"OTHER\",\"price_cents\":-1,\"stock_qty\":1,\"photos\":[]}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "500" ]
grep -F '"error":"Failed to create product"' "$RESPONSE_FILE" >/dev/null
DB_COUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM products WHERE seller_id='${SELLER_ID}' AND title='${TITLE}';")"
[ "$DB_COUNT" = "0" ]
echo "CODEVALID_TEST_ASSERTION_OK:database_write_failure_handled"

# Cleanup
psql "$DATABASE_URL" -c "ALTER TABLE products DROP CONSTRAINT IF EXISTS codevalid_products_price_nonnegative;" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
