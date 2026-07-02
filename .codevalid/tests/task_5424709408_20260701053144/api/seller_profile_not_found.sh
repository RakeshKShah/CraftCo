#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
USER_ID="user-no-profile-${CASE_SUFFIX}"
PRODUCT_ID="prod-no-profile-${CASE_SUFFIX}"
EMAIL="no-profile-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/seller_profile_not_found_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/seller_profile_not_found_${CASE_SUFFIX}.status"
TOKEN_FILE="/tmp/seller_profile_not_found_${CASE_SUFFIX}.token"
cleanup() {
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE" "$STATUS_FILE" "$TOKEN_FILE"
}
trap cleanup EXIT

# Given
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('${USER_ID}', '${EMAIL}', 'hash', 'SELLER', 'ACTIVE');"
node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"SELLER",status:"ACTIVE"}, process.env.JWT_SECRET));' "$USER_ID" "$EMAIL" > "$TOKEN_FILE"
TOKEN="$(cat "$TOKEN_FILE")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X PUT "$BASE_URL/products/${PRODUCT_ID}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  --data '{"title":"Test"}' > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "404" ]
grep -F '"error":"Seller profile not found"' "$RESPONSE_FILE" >/dev/null
echo "CODEVALID_TEST_ASSERTION_OK:seller_profile_not_found"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
