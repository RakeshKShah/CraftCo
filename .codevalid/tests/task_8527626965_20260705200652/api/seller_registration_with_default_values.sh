#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="newbie-${CASE_SUFFIX}@example.com"
PASSWORD='SecurePass123!'
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
  --data "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"SELLER\"}" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "201" ]
jq -e --arg email "$EMAIL" '
  .user.email == $email and
  .user.role == "SELLER" and
  .user.status == "PENDING" and
  .user.sellerProfile.storeName == "My Shop" and
  .user.sellerProfile.bio == ""
' "$RESPONSE_FILE" >/dev/null
SELLER_ID="$(jq -r '.user.sellerProfile.id' "$RESPONSE_FILE")"
DB_ROW="$(psql "$DATABASE_URL" -At -F '|' -c "SELECT \"storeName\", COALESCE(bio, '') FROM \"SellerProfile\" WHERE id='${SELLER_ID}';")"
[ "$DB_ROW" = "My Shop|" ]
echo "CODEVALID_TEST_ASSERTION_OK:seller_registration_with_default_values"

# Cleanup
# handled by trap
