#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="product_marked_removed_and_invisible_after_deletion"
USER_EMAIL="seller-${TEST_ID}-${CASE_SUFFIX}@example.com"
USER_PASSWORD="Password123!"
PRODUCT_ID="prod-${TEST_ID}-${CASE_SUFFIX}"
PUBLIC_BEFORE_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}_public_before.json"
PUBLIC_AFTER_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}_public_after.json"
DASHBOARD_AFTER_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}_dashboard_after.json"
REGISTER_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}_register.json"
LOGIN_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}_login.json"
RESPONSE_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/${TEST_ID}_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$PUBLIC_BEFORE_FILE" "$PUBLIC_AFTER_FILE" "$DASHBOARD_AFTER_FILE" "$REGISTER_FILE" "$LOGIN_FILE" "$RESPONSE_FILE" "$STATUS_FILE"; }
cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '${PRODUCT_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM users WHERE email = '${USER_EMAIL}';" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
curl -sS -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"${USER_EMAIL}\",\"password\":\"${USER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"Visibility Store ${CASE_SUFFIX}\",\"bio\":\"visibility test\"}" > "$REGISTER_FILE"
USER_ID="$(jq -r '.user.id' "$REGISTER_FILE")"
SELLER_ID="$(jq -r '.user.sellerProfile.id' "$REGISTER_FILE")"
psql "$DATABASE_URL" -c "UPDATE users SET status = 'ACTIVE' WHERE id = '${USER_ID}';" >/dev/null
psql "$DATABASE_URL" -c "INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible) VALUES ('${PRODUCT_ID}', '${SELLER_ID}', 'Marketplace Product ${CASE_SUFFIX}', 'should disappear from public list', 'tools', 2700, 8, '[]'::jsonb, 'ACTIVE', true);" >/dev/null
curl -sS "$BASE_URL/products" > "$PUBLIC_BEFORE_FILE"
grep -F "${PRODUCT_ID}" "$PUBLIC_BEFORE_FILE" >/dev/null
curl -sS -X POST "$BASE_URL/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"${USER_EMAIL}\",\"password\":\"${USER_PASSWORD}\"}" > "$LOGIN_FILE"
TOKEN="$(jq -r '.token' "$LOGIN_FILE")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X DELETE \
  "$BASE_URL/products/${PRODUCT_ID}" \
  -H "Authorization: Bearer ${TOKEN}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
grep -F '"success":true' "$RESPONSE_FILE" >/dev/null
DB_STATE="$(psql "$DATABASE_URL" -t -A -c "SELECT status || '|' || CASE WHEN visible THEN 'true' ELSE 'false' END FROM products WHERE id = '${PRODUCT_ID}';")"
[ "$DB_STATE" = "REMOVED|false" ]
curl -sS "$BASE_URL/products" > "$PUBLIC_AFTER_FILE"
if grep -F "${PRODUCT_ID}" "$PUBLIC_AFTER_FILE" >/dev/null; then
  echo "product still visible in public marketplace"
  exit 1
fi
curl -sS "$BASE_URL/seller/dashboard" -H "Authorization: Bearer ${TOKEN}" > "$DASHBOARD_AFTER_FILE"
grep -F '"status":"REMOVED"' "$DASHBOARD_AFTER_FILE" >/dev/null
grep -F '"visible":false' "$DASHBOARD_AFTER_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:product_marked_removed_and_invisible_after_deletion"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '${PRODUCT_ID}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -c "DELETE FROM users WHERE email = '${USER_EMAIL}';" >/dev/null 2>&1 || true
