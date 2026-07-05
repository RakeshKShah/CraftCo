#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_EMAIL="admin-${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD='AdminPass123!'
SELLER1_EMAIL="seller1-${CASE_SUFFIX}@example.com"
SELLER2_EMAIL="seller2-${CASE_SUFFIX}@example.com"
SELLER3_EMAIL="seller3-${CASE_SUFFIX}@example.com"
TMP_DIR="$(mktemp -d)"
ADMIN_RESP="$TMP_DIR/admin-register.json"
ADMIN_STATUS="$TMP_DIR/admin-register.status"
LIST_RESP="$TMP_DIR/sellers.json"
LIST_STATUS="$TMP_DIR/sellers.status"
cleanup() {
  psql "$DATABASE_URL" -c "DELETE FROM \"Product\" WHERE \"sellerId\" IN (SELECT id FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email IN ('$SELLER1_EMAIL','$SELLER2_EMAIL','$SELLER3_EMAIL')));" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email IN ('$SELLER1_EMAIL','$SELLER2_EMAIL','$SELLER3_EMAIL','$ADMIN_EMAIL'));" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE email IN ('$SELLER1_EMAIL','$SELLER2_EMAIL','$SELLER3_EMAIL','$ADMIN_EMAIL');" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Given
curl -sS -o "$ADMIN_RESP" -w '%{http_code}' -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\",\"role\":\"ADMIN\"}" > "$ADMIN_STATUS"
[ "$(cat "$ADMIN_STATUS")" = "201" ]
ADMIN_TOKEN="$(jq -r '.token' "$ADMIN_RESP")"
[ "$ADMIN_TOKEN" != "null" ]

curl -sS -o "$TMP_DIR/s1.json" -w '%{http_code}' -X POST "$BASE_URL/auth/register" -H 'Content-Type: application/json' \
  --data "{\"email\":\"${SELLER1_EMAIL}\",\"password\":\"SellerPass123!\",\"role\":\"SELLER\",\"storeName\":\"Alpha Store ${CASE_SUFFIX}\",\"bio\":\"Alpha bio\"}" > "$TMP_DIR/s1.status"
[ "$(cat "$TMP_DIR/s1.status")" = "201" ]

curl -sS -o "$TMP_DIR/s2.json" -w '%{http_code}' -X POST "$BASE_URL/auth/register" -H 'Content-Type: application/json' \
  --data "{\"email\":\"${SELLER2_EMAIL}\",\"password\":\"SellerPass123!\",\"role\":\"SELLER\",\"storeName\":\"Beta Store ${CASE_SUFFIX}\",\"bio\":\"Beta bio\"}" > "$TMP_DIR/s2.status"
[ "$(cat "$TMP_DIR/s2.status")" = "201" ]

curl -sS -o "$TMP_DIR/s3.json" -w '%{http_code}' -X POST "$BASE_URL/auth/register" -H 'Content-Type: application/json' \
  --data "{\"email\":\"${SELLER3_EMAIL}\",\"password\":\"SellerPass123!\",\"role\":\"SELLER\",\"storeName\":\"Gamma Store ${CASE_SUFFIX}\",\"bio\":\"Gamma bio\"}" > "$TMP_DIR/s3.status"
[ "$(cat "$TMP_DIR/s3.status")" = "201" ]

psql "$DATABASE_URL" -c "UPDATE \"User\" SET status='ACTIVE' WHERE email='${SELLER1_EMAIL}';" >/dev/null
psql "$DATABASE_URL" -c "UPDATE \"User\" SET status='PENDING' WHERE email='${SELLER2_EMAIL}';" >/dev/null
psql "$DATABASE_URL" -c "UPDATE \"User\" SET status='SUSPENDED' WHERE email='${SELLER3_EMAIL}';" >/dev/null

# When
curl -sS -o "$LIST_RESP" -w '%{http_code}' "$BASE_URL/admin/sellers" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" > "$LIST_STATUS"

# Then
[ "$(cat "$LIST_STATUS")" = "200" ]
jq -e 'type == "array"' "$LIST_RESP" >/dev/null
jq -e --arg e "$SELLER1_EMAIL" '.[] | select(.email == $e) | (.id | type == "string") and (.user_id | type == "string") and (.store_name | type == "string") and ((.bio == null) or (.bio | type == "string")) and (.status == "ACTIVE") and (.product_count | type == "number") and (.created_at | type == "string")' "$LIST_RESP" >/dev/null
jq -e --arg e "$SELLER2_EMAIL" '.[] | select(.email == $e and .status == "PENDING")' "$LIST_RESP" >/dev/null
jq -e --arg e "$SELLER3_EMAIL" '.[] | select(.email == $e and .status == "SUSPENDED")' "$LIST_RESP" >/dev/null
COUNT_MATCH="$(jq --arg e1 "$SELLER1_EMAIL" --arg e2 "$SELLER2_EMAIL" --arg e3 "$SELLER3_EMAIL" '[.[] | select(.email == $e1 or .email == $e2 or .email == $e3)] | length' "$LIST_RESP")"
[ "$COUNT_MATCH" = "3" ]

echo "CODEVALID_TEST_ASSERTION_OK:admin_retrieves_all_sellers_successfully"

# Cleanup
# handled by trap
