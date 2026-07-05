#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_ID="buyer-missingprod-${CASE_SUFFIX}"
MISSING_PRODUCT_ID="prod-nonexistent-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/checkout_fails_nonexistent_product_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/checkout_fails_nonexistent_product_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
BUYER_TOKEN="$(node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id: process.argv[1], email: 'buyer+'+process.argv[2]+'@example.com', role: 'BUYER', status: 'ACTIVE'}, 'dev-secret', {expiresIn:'7d'}));" "$BUYER_ID" "$CASE_SUFFIX")"
psql "$DATABASE_URL" -c "INSERT INTO \"User\" (id, email, password, role, status, \"createdAt\") VALUES ('${BUYER_ID}', 'buyer+${CASE_SUFFIX}@example.com', 'pw', 'BUYER', 'ACTIVE', NOW());"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/orders/checkout" \
  -H "Authorization: Bearer ${BUYER_TOKEN}" \
  -H 'Content-Type: application/json' \
  --data "{\"items\":[{\"product_id\":\"${MISSING_PRODUCT_ID}\",\"qty\":1}]}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "400" ]
grep -F "Product ${MISSING_PRODUCT_ID} unavailable" "$RESPONSE_FILE" >/dev/null
ORDER_COUNT="$(psql "$DATABASE_URL" -At -c "SELECT COUNT(*) FROM \"Order\" WHERE buyer_id = '${BUYER_ID}';")"
[ "$ORDER_COUNT" = '0' ]
echo 'CODEVALID_TEST_ASSERTION_OK:checkout_fails_nonexistent_product'

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE id = '${BUYER_ID}';"
