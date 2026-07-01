#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
USER_ID="seller-pending-${CASE_SUFFIX}"
SELLER_ID="profile-pending-${CASE_SUFFIX}"
PRODUCT_ID="prod-pending-${CASE_SUFFIX}"
EMAIL="seller-pending-${CASE_SUFFIX}@example.com"
TOKEN_FILE="/tmp/pending_seller_cannot_update_product_${CASE_SUFFIX}.token"
RESPONSE_FILE="/tmp/pending_seller_cannot_update_product_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/pending_seller_cannot_update_product_${CASE_SUFFIX}.status"
cleanup() {
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id='${PRODUCT_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
  rm -f "$TOKEN_FILE" "$RESPONSE_FILE" "$STATUS_FILE"
}
trap cleanup EXIT

# Given
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('${USER_ID}', '${EMAIL}', 'hash', 'SELLER', 'PENDING');"
psql "$DATABASE_URL" -c "INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('${SELLER_ID}', '${USER_ID}', 'Pending Store ${CASE_SUFFIX}', 'Pending bio ${CASE_SUFFIX}');"
psql "$DATABASE_URL" -c "INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible) VALUES ('${PRODUCT_ID}', '${SELLER_ID}', 'Pending Original', 'Pending description', 'BOOKS', 1500, 4, '[\"https://example.com/pending.jpg\"]', 'ACTIVE', true);"
node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"SELLER",status:"PENDING"}, process.env.JWT_SECRET));' "$USER_ID" "$EMAIL" > "$TOKEN_FILE"
TOKEN="$(cat "$TOKEN_FILE")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X PUT "$BASE_URL/products/${PRODUCT_ID}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  --data '{"title":"Attempted Update"}' > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "403" ]
grep -F '"error":"Seller account must be active"' "$RESPONSE_FILE" >/dev/null
DB_TITLE="$(psql "$DATABASE_URL" -t -A -c "SELECT title FROM products WHERE id='${PRODUCT_ID}';")"
[ "$DB_TITLE" = 'Pending Original' ]
echo "CODEVALID_TEST_ASSERTION_OK:pending_seller_cannot_update_product"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM products WHERE id='${PRODUCT_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
