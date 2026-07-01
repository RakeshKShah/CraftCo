#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
USER_ID="seller-noprofile-${CASE_SUFFIX}"
OWNER_USER_ID="seller-owner-noprofile-${CASE_SUFFIX}"
OWNER_SELLER_ID="profile-owner-noprofile-${CASE_SUFFIX}"
PRODUCT_ID="prod-noprofile-${CASE_SUFFIX}"
EMAIL="seller-noprofile-${CASE_SUFFIX}@example.com"
OWNER_EMAIL="seller-owner-noprofile-${CASE_SUFFIX}@example.com"
TOKEN_FILE="/tmp/seller_without_profile_cannot_update_${CASE_SUFFIX}.token"
RESPONSE_FILE="/tmp/seller_without_profile_cannot_update_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/seller_without_profile_cannot_update_${CASE_SUFFIX}.status"
cleanup() {
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id='${PRODUCT_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${OWNER_SELLER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id IN ('${USER_ID}','${OWNER_USER_ID}');" >/dev/null 2>&1 || true
  rm -f "$TOKEN_FILE" "$RESPONSE_FILE" "$STATUS_FILE"
}
trap cleanup EXIT

# Given
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('${USER_ID}', '${EMAIL}', 'hash', 'SELLER', 'ACTIVE');"
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('${OWNER_USER_ID}', '${OWNER_EMAIL}', 'hash', 'SELLER', 'ACTIVE');"
psql "$DATABASE_URL" -c "INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('${OWNER_SELLER_ID}', '${OWNER_USER_ID}', 'Owner Store ${CASE_SUFFIX}', 'Owner bio ${CASE_SUFFIX}');"
psql "$DATABASE_URL" -c "INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible) VALUES ('${PRODUCT_ID}', '${OWNER_SELLER_ID}', 'No Profile Original', 'Protected product', 'TOYS', 2700, 5, '[\"https://example.com/noprofile.jpg\"]', 'ACTIVE', true);"
node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"SELLER",status:"ACTIVE"}, process.env.JWT_SECRET));' "$USER_ID" "$EMAIL" > "$TOKEN_FILE"
TOKEN="$(cat "$TOKEN_FILE")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X PUT "$BASE_URL/products/${PRODUCT_ID}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  --data '{"title":"No Profile Update"}' > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "404" ]
grep -F '"error":"Seller profile not found"' "$RESPONSE_FILE" >/dev/null
DB_TITLE="$(psql "$DATABASE_URL" -t -A -c "SELECT title FROM products WHERE id='${PRODUCT_ID}';")"
[ "$DB_TITLE" = 'No Profile Original' ]
echo "CODEVALID_TEST_ASSERTION_OK:seller_without_profile_cannot_update"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM products WHERE id='${PRODUCT_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${OWNER_SELLER_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM users WHERE id IN ('${USER_ID}','${OWNER_USER_ID}');" >/dev/null 2>&1 || true
