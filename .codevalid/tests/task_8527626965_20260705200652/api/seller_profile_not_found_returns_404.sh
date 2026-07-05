#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="no-profile-${CASE_SUFFIX}@example.com"
USER_ID="no-profile-user-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/seller_profile_not_found_returns_404_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/seller_profile_not_found_returns_404_${CASE_SUFFIX}.status"
cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
trap cleanup_files EXIT

# Given
PASSWORD_HASH='not-used-by-auth'
psql "$DATABASE_URL" -c "INSERT INTO \"User\" (id, email, \"passwordHash\", role, status, \"createdAt\") VALUES ('${USER_ID}', '${EMAIL}', '${PASSWORD_HASH}', 'SELLER', 'ACTIVE', NOW());" >/dev/null
TOKEN="$(node -e "const jwt=require('jsonwebtoken'); process.stdout.write(jwt.sign({id:'${USER_ID}',email:'${EMAIL}',role:'SELLER',status:'ACTIVE'}, process.env.JWT_SECRET || 'dev-secret'));" )"
[ -n "$TOKEN" ]

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  -d "{\"title\":\"No Profile Product ${CASE_SUFFIX}\",\"description\":\"Should fail\",\"category\":\"HOME_DECOR\",\"price_cents\":4500,\"stock_qty\":10,\"photos\":[\"https://example.com/photo1.jpg\"]}" \
  > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "404" ]
jq -e '.error == "Seller profile not found"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:seller_profile_not_found_returns_404"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE id = '${USER_ID}';" >/dev/null
