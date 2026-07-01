#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
USER_ID="user-buyer-${CASE_SUFFIX}"
EMAIL="buyer-${CASE_SUFFIX}@example.com"
TOKEN_FILE="/tmp/non_seller_role_forbidden_${CASE_SUFFIX}.token"
RESPONSE_FILE="/tmp/non_seller_role_forbidden_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/non_seller_role_forbidden_${CASE_SUFFIX}.status"
cleanup() {
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE title='Buyer Product ${CASE_SUFFIX}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
  rm -f "$TOKEN_FILE" "$RESPONSE_FILE" "$STATUS_FILE"
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
  --data "{\"title\":\"Buyer Product ${CASE_SUFFIX}\",\"description\":\"Minimal\",\"category\":\"MISC\",\"price_cents\":100,\"stock_qty\":1,\"photos\":[]}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "403" ]
grep -F '"error":"Seller access required"' "$RESPONSE_FILE" >/dev/null
DB_COUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM products WHERE title='Buyer Product ${CASE_SUFFIX}';")"
[ "$DB_COUNT" = "0" ]
echo "CODEVALID_TEST_ASSERTION_OK:non_seller_role_forbidden"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
