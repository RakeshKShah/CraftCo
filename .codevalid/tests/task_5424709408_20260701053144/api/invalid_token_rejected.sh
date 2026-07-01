#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
USER_ID="seller-invalid-token-${CASE_SUFFIX}"
SELLER_ID="profile-invalid-token-${CASE_SUFFIX}"
PRODUCT_ID="prod-invalid-token-${CASE_SUFFIX}"
EMAIL="seller-invalid-token-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/invalid_token_rejected_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/invalid_token_rejected_${CASE_SUFFIX}.status"
cleanup() {
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id='${PRODUCT_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
trap cleanup EXIT

# Given
psql "$DATABASE_URL" -c "INSERT INTO users (id, email, password_hash, role, status) VALUES ('${USER_ID}', '${EMAIL}', 'hash', 'SELLER', 'ACTIVE');"
psql "$DATABASE_URL" -c "INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('${SELLER_ID}', '${USER_ID}', 'Token Store ${CASE_SUFFIX}', 'Token bio ${CASE_SUFFIX}');"
psql "$DATABASE_URL" -c "INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible) VALUES ('${PRODUCT_ID}', '${SELLER_ID}', 'Token Original', 'Token description', 'ELECTRONICS', 4500, 2, '[\"https://example.com/token.jpg\"]', 'ACTIVE', true);"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X PUT "$BASE_URL/products/${PRODUCT_ID}" \
  -H 'Authorization: Bearer invalid_token_string' \
  -H 'Content-Type: application/json' \
  --data '{"title":"Bad Token Attempt"}' > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "401" ]
grep -F '"error":"Invalid token"' "$RESPONSE_FILE" >/dev/null
DB_TITLE="$(psql "$DATABASE_URL" -t -A -c "SELECT title FROM products WHERE id='${PRODUCT_ID}';")"
[ "$DB_TITLE" = 'Token Original' ]
echo "CODEVALID_TEST_ASSERTION_OK:invalid_token_rejected"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM products WHERE id='${PRODUCT_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM users WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
