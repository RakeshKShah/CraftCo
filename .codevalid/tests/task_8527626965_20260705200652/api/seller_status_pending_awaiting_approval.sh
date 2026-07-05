#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="pending-seller-${CASE_SUFFIX}@example.com"
PASSWORD='SellerPass789!'
STORE_NAME="Awaiting Approval Shop ${CASE_SUFFIX}"
TMP_DIR="$(mktemp -d)"
REGISTER_RESPONSE="$TMP_DIR/register.json"
REGISTER_STATUS="$TMP_DIR/register.status"
CREATE_RESPONSE="$TMP_DIR/create.json"
CREATE_STATUS="$TMP_DIR/create.status"
cleanup() {
  PRODUCT_ID="$(jq -r '.id // empty' "$CREATE_RESPONSE" 2>/dev/null || true)"
  SELLER_ID="$(jq -r '.user.sellerProfile.id // empty' "$REGISTER_RESPONSE" 2>/dev/null || true)"
  USER_ID="$(jq -r '.user.id // empty' "$REGISTER_RESPONSE" 2>/dev/null || true)"
  [ -n "$PRODUCT_ID" ] && psql "$DATABASE_URL" -c "DELETE FROM \"Product\" WHERE id='${PRODUCT_ID}';" >/dev/null 2>&1 || true
  [ -n "$SELLER_ID" ] && psql "$DATABASE_URL" -c "DELETE FROM \"SellerProfile\" WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
  [ -n "$USER_ID" ] && psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email='${EMAIL}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE email='${EMAIL}';" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Given
psql "$DATABASE_URL" -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email='${EMAIL}');" >/dev/null
psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE email='${EMAIL}';" >/dev/null
curl -sS -o "$REGISTER_RESPONSE" -w '%{http_code}' -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\"}" > "$REGISTER_STATUS"
[ "$(cat "$REGISTER_STATUS")" = "201" ]
TOKEN="$(jq -r '.token' "$REGISTER_RESPONSE")"
USER_ID="$(jq -r '.user.id' "$REGISTER_RESPONSE")"

# When
curl -sS -o "$CREATE_RESPONSE" -w '%{http_code}' -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  --data "{\"title\":\"Blocked Product ${CASE_SUFFIX}\",\"description\":\"Should be blocked\",\"category\":\"CLOTHING\",\"price_cents\":1500,\"stock_qty\":1,\"photos\":[]}" > "$CREATE_STATUS"

# Then
[ "$(jq -r '.user.status' "$REGISTER_RESPONSE")" = "PENDING" ]
DB_STATUS="$(psql "$DATABASE_URL" -At -c "SELECT status::text FROM \"User\" WHERE id='${USER_ID}';")"
[ "$DB_STATUS" = "PENDING" ]
[ "$(cat "$CREATE_STATUS")" = "403" ]
jq -e '.error == "Seller account must be approved before listing products"' "$CREATE_RESPONSE" >/dev/null
echo "CODEVALID_TEST_ASSERTION_OK:seller_status_pending_awaiting_approval"

# Cleanup
# handled by trap
