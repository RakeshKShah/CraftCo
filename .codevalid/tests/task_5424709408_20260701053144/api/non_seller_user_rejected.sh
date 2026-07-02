#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
USER_ID="buyer-${CASE_SUFFIX}"
EMAIL="buyer-${CASE_SUFFIX}@example.com"
TITLE="Buyer Forbidden ${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/non_seller_user_rejected_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/non_seller_user_rejected_${CASE_SUFFIX}.status"
TOKEN_FILE="/tmp/non_seller_user_rejected_${CASE_SUFFIX}.token"
cleanup() {
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE" "$STATUS_FILE" "$TOKEN_FILE"
}
trap cleanup EXIT

# Given
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('${USER_ID}', '${EMAIL}', 'hash', 'BUYER', 'ACTIVE');"
node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"BUYER",status:"ACTIVE"}, process.env.JWT_SECRET));' "$USER_ID" "$EMAIL" > "$TOKEN_FILE"
TOKEN="$(cat "$TOKEN_FILE")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  --data "{\"title\":\"${TITLE}\",\"description\":\"Forbidden\",\"category\":\"HOME_GOODS\",\"price_cents\":999,\"stock_qty\":1,\"photos\":[]}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "403" ]
grep -F '"error":"Seller access required"' "$RESPONSE_FILE" >/dev/null
echo "CODEVALID_TEST_ASSERTION_OK:non_seller_user_rejected"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
