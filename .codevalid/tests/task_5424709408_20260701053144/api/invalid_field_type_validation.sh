#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
USER_ID="user-validation-type-${CASE_SUFFIX}"
SELLER_ID="seller-validation-type-${CASE_SUFFIX}"
EMAIL="validation-type-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/invalid_field_type_validation_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/invalid_field_type_validation_${CASE_SUFFIX}.status"
TOKEN_FILE="/tmp/invalid_field_type_validation_${CASE_SUFFIX}.token"
cleanup() {
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE" "$STATUS_FILE" "$TOKEN_FILE"
}
trap cleanup EXIT

# Given
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('${USER_ID}', '${EMAIL}', 'hash', 'SELLER', 'ACTIVE');"
psql "$DATABASE_URL" -c "INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('${SELLER_ID}', '${USER_ID}', 'Validation Type Store ${CASE_SUFFIX}', 'Validation bio');"
node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"SELLER",status:"ACTIVE",sellerProfileId:process.argv[3]}, process.env.JWT_SECRET));' "$USER_ID" "$EMAIL" "$SELLER_ID" > "$TOKEN_FILE"
TOKEN="$(cat "$TOKEN_FILE")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  --data '{"title":"Test","description":"Type mismatch","category":"HOME_GOODS","price_cents":"free","stock_qty":5,"photos":[]}' > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "400" ]
grep -F '"error":' "$RESPONSE_FILE" >/dev/null
if grep -F '"error":"Failed to create product"' "$RESPONSE_FILE" >/dev/null; then
  exit 1
fi
echo "CODEVALID_TEST_ASSERTION_OK:invalid_field_type_validation"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
