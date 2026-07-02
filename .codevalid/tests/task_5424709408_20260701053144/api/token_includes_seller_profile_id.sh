#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="seller-token-${CASE_SUFFIX}@test.com"
RESPONSE_FILE="/tmp/token_includes_seller_profile_id_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/token_includes_seller_profile_id_${CASE_SUFFIX}.status"
PAYLOAD_FILE="/tmp/token_includes_seller_profile_id_payload_${CASE_SUFFIX}.json"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE" "$PAYLOAD_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email = '${SELLER_EMAIL}');" >/dev/null
psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE email = '${SELLER_EMAIL}';" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"SecurePass123!\",\"role\":\"SELLER\",\"storeName\":\"Token Test Shop\"}" > "$STATUS_FILE"
TOKEN="$(jq -r '.token' "$RESPONSE_FILE")"
USER_PROFILE_ID="$(jq -r '.user.sellerProfile.id' "$RESPONSE_FILE")"
PAYLOAD_SEGMENT="$(printf '%s' "$TOKEN" | cut -d '.' -f2)"
PADDING=$(( (4 - ${#PAYLOAD_SEGMENT} % 4) % 4 ))
PAD=''
if [ "$PADDING" -eq 2 ]; then PAD='=='; elif [ "$PADDING" -eq 1 ]; then PAD='='; elif [ "$PADDING" -eq 3 ]; then PAD='==='; fi
printf '%s%s' "$PAYLOAD_SEGMENT" "$PAD" | tr '_-' '/+' | base64 -d > "$PAYLOAD_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "201" ]
[ "$TOKEN" != "null" ]
[ "$USER_PROFILE_ID" != "null" ]
jq -e '.id and .email and .role == "SELLER" and .status == "PENDING" and .sellerProfileId' "$PAYLOAD_FILE" >/dev/null
[ "$(jq -r '.sellerProfileId' "$PAYLOAD_FILE")" = "$USER_PROFILE_ID" ]
[ "$(jq -r '.email' "$PAYLOAD_FILE")" = "$SELLER_EMAIL" ]

echo "CODEVALID_TEST_ASSERTION_OK:token_includes_seller_profile_id"

# Cleanup
psql "$DATABASE_URL" -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email = '${SELLER_EMAIL}');" >/dev/null
psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE email = '${SELLER_EMAIL}';" >/dev/null
