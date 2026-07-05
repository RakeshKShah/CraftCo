#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="seller-${CASE_SUFFIX}@example.com"
PASSWORD='SecurePass123!'
STORE_NAME="Artisan Goods ${CASE_SUFFIX}"
BIO="Handmade crafts and vintage treasures ${CASE_SUFFIX}"
TMP_DIR="$(mktemp -d)"
RESPONSE_FILE="$TMP_DIR/response.json"
STATUS_FILE="$TMP_DIR/status.txt"
cleanup() {
  USER_ID="$(jq -r '.user.id // empty' "$RESPONSE_FILE" 2>/dev/null || true)"
  SELLER_ID="$(jq -r '.user.sellerProfile.id // empty' "$RESPONSE_FILE" 2>/dev/null || true)"
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

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\",\"bio\":\"${BIO}\"}" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "201" ]
TOKEN="$(jq -r '.token' "$RESPONSE_FILE")"
[ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]
jq -e --arg email "$EMAIL" --arg store "$STORE_NAME" --arg bio "$BIO" '
  .user.email == $email and
  .user.role == "SELLER" and
  .user.status == "PENDING" and
  .user.sellerProfile.storeName == $store and
  .user.sellerProfile.bio == $bio and
  (.user.sellerProfile.id | type == "string")
' "$RESPONSE_FILE" >/dev/null
USER_ID="$(jq -r '.user.id' "$RESPONSE_FILE")"
DB_ROW="$(psql "$DATABASE_URL" -At -F '|' -c "SELECT email, role::text, status::text FROM \"User\" WHERE id='${USER_ID}';")"
[ "$DB_ROW" = "${EMAIL}|SELLER|PENDING" ]
echo "CODEVALID_TEST_ASSERTION_OK:seller_registration_success_with_all_fields"

# Cleanup
# handled by trap
