#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_EMAIL="suspend-empty-admin-${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD='AdminPass123!'
SELLER_EMAIL="suspend-empty-seller-${CASE_SUFFIX}@example.com"
SELLER_PASSWORD='SellerPass123!'
TMP_DIR="$(mktemp -d)"
ADMIN_RESP="$TMP_DIR/admin.json"
SELLER_RESP="$TMP_DIR/seller.json"
APPROVE_RESP="$TMP_DIR/approve.json"
RESP_FILE="$TMP_DIR/suspend.json"
STATUS_FILE="$TMP_DIR/suspend.status"
cleanup() {
  SELLER_ID="$(jq -r '.user.sellerProfile.id // empty' "$SELLER_RESP" 2>/dev/null || true)"
  USER_ID="$(jq -r '.user.id // empty' "$SELLER_RESP" 2>/dev/null || true)"
  [ -n "$SELLER_ID" ] && psql "$DATABASE_URL" -c "DELETE FROM \"Product\" WHERE \"sellerId\"='${SELLER_ID}'; DELETE FROM \"SellerProfile\" WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
  [ -n "$USER_ID" ] && psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE id='${USER_ID}';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email='${ADMIN_EMAIL}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE email IN ('${ADMIN_EMAIL}','${SELLER_EMAIL}');" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Given
curl -sS -o "$ADMIN_RESP" -w '%{http_code}' -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\",\"role\":\"ADMIN\"}" > "$TMP_DIR/admin.status"
[ "$(cat "$TMP_DIR/admin.status")" = "201" ]
ADMIN_TOKEN="$(jq -r '.token' "$ADMIN_RESP")"

curl -sS -o "$SELLER_RESP" -w '%{http_code}' -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"Suspend Empty Store ${CASE_SUFFIX}\",\"bio\":\"bio\"}" > "$TMP_DIR/seller.status"
[ "$(cat "$TMP_DIR/seller.status")" = "201" ]
SELLER_ID="$(jq -r '.user.sellerProfile.id' "$SELLER_RESP")"
USER_ID="$(jq -r '.user.id' "$SELLER_RESP")"

curl -sS -o "$APPROVE_RESP" -w '%{http_code}' -X PUT "$BASE_URL/admin/sellers/${SELLER_ID}" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  --data '{"status":"ACTIVE"}' > "$TMP_DIR/approve.status"
[ "$(cat "$TMP_DIR/approve.status")" = "200" ]
PRODUCT_COUNT_BEFORE="$(psql "$DATABASE_URL" -At -c "SELECT COUNT(*) FROM \"Product\" WHERE \"sellerId\"='${SELLER_ID}';")"
[ "$PRODUCT_COUNT_BEFORE" = "0" ]

# When
curl -sS -o "$RESP_FILE" -w '%{http_code}' -X PUT "$BASE_URL/admin/sellers/${SELLER_ID}" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  --data '{"status":"SUSPENDED"}' > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
jq -e --arg id "$SELLER_ID" '.id == $id and .status == "SUSPENDED"' "$RESP_FILE" >/dev/null
DB_STATUS="$(psql "$DATABASE_URL" -At -c "SELECT status FROM \"User\" WHERE id='${USER_ID}';")"
[ "$DB_STATUS" = "SUSPENDED" ]
PRODUCT_COUNT_AFTER="$(psql "$DATABASE_URL" -At -c "SELECT COUNT(*) FROM \"Product\" WHERE \"sellerId\"='${SELLER_ID}';")"
[ "$PRODUCT_COUNT_AFTER" = "0" ]
echo "CODEVALID_TEST_ASSERTION_OK:suspend_without_products_succeeds"

# Cleanup
# handled by trap
