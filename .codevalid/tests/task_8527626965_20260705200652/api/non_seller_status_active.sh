#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="buyer-${CASE_SUFFIX}@example.com"
PASSWORD='BuyerPass101!'
TMP_DIR="$(mktemp -d)"
RESPONSE_FILE="$TMP_DIR/response.json"
STATUS_FILE="$TMP_DIR/status.txt"
cleanup() {
  USER_ID="$(jq -r '.user.id // empty' "$RESPONSE_FILE" 2>/dev/null || true)"
  [ -n "$USER_ID" ] && psql "$DATABASE_URL" -c "DELETE FROM \"SellerProfile\" WHERE \"userId\"='${USER_ID}';" >/dev/null 2>&1 || true
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
  --data "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"BUYER\"}" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "201" ]
jq -e --arg email "$EMAIL" '
  .user.email == $email and
  .user.role == "BUYER" and
  .user.status == "ACTIVE" and
  (.user.sellerProfile == null)
' "$RESPONSE_FILE" >/dev/null
USER_ID="$(jq -r '.user.id' "$RESPONSE_FILE")"
DB_STATUS="$(psql "$DATABASE_URL" -At -c "SELECT status::text FROM \"User\" WHERE id='${USER_ID}';")"
[ "$DB_STATUS" = "ACTIVE" ]
SELLER_PROFILE_COUNT="$(psql "$DATABASE_URL" -At -c "SELECT COUNT(*) FROM \"SellerProfile\" WHERE \"userId\"='${USER_ID}';")"
[ "$SELLER_PROFILE_COUNT" = "0" ]
echo "CODEVALID_TEST_ASSERTION_OK:non_seller_status_active"

# Cleanup
# handled by trap
