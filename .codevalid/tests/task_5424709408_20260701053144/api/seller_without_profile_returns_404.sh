#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="seller_without_profile_returns_404"
USER_EMAIL="seller-${TEST_ID}-${CASE_SUFFIX}@example.com"
USER_PASSWORD="Password123!"
OTHER_SELLER_EMAIL="owner-${TEST_ID}-${CASE_SUFFIX}@example.com"
OTHER_SELLER_PASSWORD="Password123!"
PRODUCT_ID="prod-${TEST_ID}-${CASE_SUFFIX}"
REGISTER_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}_register.json"
LOGIN_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}_login.json"
OWNER_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}_owner.json"
RESPONSE_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$REGISTER_FILE" "$LOGIN_FILE" "$OWNER_FILE" "$RESPONSE_FILE" "$STATUS_FILE"; }
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '${PRODUCT_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE email IN ('${USER_EMAIL}', '${OTHER_SELLER_EMAIL}');" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
curl -sS -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"${USER_EMAIL}\",\"password\":\"${USER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"Profileless Store ${CASE_SUFFIX}\",\"bio\":\"will remove profile\"}" > "$REGISTER_FILE"
USER_ID="$(jq -r '.user.id' "$REGISTER_FILE")"
psql "$DATABASE_URL" -c "UPDATE users SET status = 'ACTIVE' WHERE id = '${USER_ID}';" >/dev/null
psql "$DATABASE_URL" -c "DELETE FROM seller_profiles WHERE user_id = '${USER_ID}';" >/dev/null
curl -sS -X POST "$BASE_URL/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"${USER_EMAIL}\",\"password\":\"${USER_PASSWORD}\"}" > "$LOGIN_FILE"
TOKEN="$(jq -r '.token' "$LOGIN_FILE")"
curl -sS -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"${OTHER_SELLER_EMAIL}\",\"password\":\"${OTHER_SELLER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"Owner Store ${CASE_SUFFIX}\",\"bio\":\"owner setup\"}" > "$OWNER_FILE"
OWNER_USER_ID="$(jq -r '.user.id' "$OWNER_FILE")"
OWNER_SELLER_ID="$(jq -r '.user.sellerProfile.id' "$OWNER_FILE")"
psql "$DATABASE_URL" -c "UPDATE users SET status = 'ACTIVE' WHERE id = '${OWNER_USER_ID}';" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible) VALUES ('${PRODUCT_ID}', '${OWNER_SELLER_ID}', 'Existing Product ${CASE_SUFFIX}', 'product exists but actor has no profile', 'tools', 2300, 1, '[]'::jsonb, 'ACTIVE', true);" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X DELETE \
  "$BASE_URL/products/${PRODUCT_ID}" \
  -H "Authorization: Bearer ${TOKEN}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "404" ]
grep -F '"error":"Seller profile not found"' "$RESPONSE_FILE" >/dev/null
DB_STATE="$(psql "$DATABASE_URL" -t -A -c "SELECT status || '|' || CASE WHEN visible THEN 'true' ELSE 'false' END FROM products WHERE id = '${PRODUCT_ID}';")"
[ "$DB_STATE" = "ACTIVE|true" ]

echo "CODEVALID_TEST_ASSERTION_OK:seller_without_profile_returns_404"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '${PRODUCT_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM users WHERE email IN ('${USER_EMAIL}', '${OTHER_SELLER_EMAIL}');" >/dev/null 2>&1 || true
