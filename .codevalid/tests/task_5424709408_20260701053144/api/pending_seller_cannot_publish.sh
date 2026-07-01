#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
USER_ID="user-pending-${CASE_SUFFIX}"
SELLER_ID="seller-profile-pending-${CASE_SUFFIX}"
EMAIL="pending-${CASE_SUFFIX}@example.com"
TOKEN_FILE="/tmp/pending_seller_cannot_publish_${CASE_SUFFIX}.token"
RESPONSE_FILE="/tmp/pending_seller_cannot_publish_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/pending_seller_cannot_publish_${CASE_SUFFIX}.status"
cleanup() {
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE title='Pending Product ${CASE_SUFFIX}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
  rm -f "$TOKEN_FILE" "$RESPONSE_FILE" "$STATUS_FILE"
}
trap cleanup EXIT

# Given
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('${USER_ID}', '${EMAIL}', 'hash', 'SELLER', 'PENDING');"
psql "$DATABASE_URL" -c "INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('${SELLER_ID}', '${USER_ID}', 'Pending Store ${CASE_SUFFIX}', 'Pending bio ${CASE_SUFFIX}');"
node -e 'const jwt=require("jsonwebtoken"); process.stdout.write(jwt.sign({id:process.argv[1],email:process.argv[2],role:"SELLER",status:"PENDING"}, process.env.JWT_SECRET));' "$USER_ID" "$EMAIL" > "$TOKEN_FILE"
TOKEN="$(cat "$TOKEN_FILE")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  --data "{\"title\":\"Pending Product ${CASE_SUFFIX}\",\"description\":\"...\",\"category\":\"ART\",\"price_cents\":1000,\"stock_qty\":5,\"photos\":[]}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "403" ]
grep -F '"error":"Seller account must be approved before listing products"' "$RESPONSE_FILE" >/dev/null
DB_COUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM products WHERE title='Pending Product ${CASE_SUFFIX}';")"
[ "$DB_COUNT" = "0" ]
echo "CODEVALID_TEST_ASSERTION_OK:pending_seller_cannot_publish"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
