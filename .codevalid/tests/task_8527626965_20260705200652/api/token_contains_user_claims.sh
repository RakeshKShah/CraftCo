#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="token-test-${CASE_SUFFIX}@example.com"
PASSWORD='TokenPass123!'
STORE_NAME="Token Shop ${CASE_SUFFIX}"
TMP_DIR="$(mktemp -d)"
RESPONSE_FILE="$TMP_DIR/response.json"
STATUS_FILE="$TMP_DIR/status.txt"
PAYLOAD_FILE="$TMP_DIR/token-payload.json"
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
  --data "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\"}" > "$STATUS_FILE"
TOKEN="$(jq -r '.token' "$RESPONSE_FILE")"
PAYLOAD_B64="$(printf '%s' "$TOKEN" | cut -d '.' -f 2 | tr '_-' '/+')"
PADDING_MOD="$(( ${#PAYLOAD_B64} % 4 ))"
if [ "$PADDING_MOD" -eq 2 ]; then
  PAYLOAD_B64="${PAYLOAD_B64}=="
elif [ "$PADDING_MOD" -eq 3 ]; then
  PAYLOAD_B64="${PAYLOAD_B64}="
elif [ "$PADDING_MOD" -eq 1 ]; then
  PAYLOAD_B64="${PAYLOAD_B64}==="
fi
printf '%s' "$PAYLOAD_B64" | base64 -d > "$PAYLOAD_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "201" ]
USER_ID="$(jq -r '.user.id' "$RESPONSE_FILE")"
SELLER_ID="$(jq -r '.user.sellerProfile.id' "$RESPONSE_FILE")"
jq -e --arg id "$USER_ID" --arg email "$EMAIL" --arg sellerId "$SELLER_ID" '
  .id == $id and
  .email == $email and
  .role == "SELLER" and
  .status == "PENDING" and
  .sellerProfileId == $sellerId
' "$PAYLOAD_FILE" >/dev/null
echo "CODEVALID_TEST_ASSERTION_OK:token_contains_user_claims"

# Cleanup
# handled by trap
