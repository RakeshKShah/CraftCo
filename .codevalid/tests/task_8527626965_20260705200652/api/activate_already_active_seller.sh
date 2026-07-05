#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_EMAIL="activate-active-admin-${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD='AdminPass123!'
SELLER_EMAIL="activate-active-seller-${CASE_SUFFIX}@example.com"
SELLER_PASSWORD='SellerPass123!'
TMP_DIR="$(mktemp -d)"
ADMIN_RESP="$TMP_DIR/admin.json"
SELLER_RESP="$TMP_DIR/seller.json"
CREATE_RESP="$TMP_DIR/create.json"
RESP_FILE="$TMP_DIR/activate.json"
STATUS_FILE="$TMP_DIR/activate.status"
cleanup() {
  SELLER_ID="$(jq -r '.user.sellerProfile.id // empty' "$SELLER_RESP" 2>/dev/null || true)"
  USER_ID="$(jq -r '.user.id // empty' "$SELLER_RESP" 2>/dev/null || true)"
  PRODUCT_ID="$(jq -r '.id // empty' "$CREATE_RESP" 2>/dev/null || true)"
  [ -n "$PRODUCT_ID" ] && psql "$DATABASE_URL" -c "DELETE FROM \"Product\" WHERE id='${PRODUCT_ID}';" >/dev/null 2>&1 || true
  [ -n "$SELLER_ID" ] && psql "$DATABASE_URL" -c "DELETE FROM \"SellerProfile\" WHERE id='${SELLER_ID}';" >/dev/null 2>&1 || true
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
  --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"Already Active Store ${CASE_SUFFIX}\",\"bio\":\"bio\"}" > "$TMP_DIR/seller.status"
[ "$(cat "$TMP_DIR/seller.status")" = "201" ]
SELLER_TOKEN="$(jq -r '.token' "$SELLER_RESP")"
SELLER_ID="$(jq -r '.user.sellerProfile.id' "$SELLER_RESP")"
USER_ID="$(jq -r '.user.id' "$SELLER_RESP")"

curl -sS -o "$TMP_DIR/approve.json" -w '%{http_code}' -X PUT "$BASE_URL/admin/sellers/${SELLER_ID}" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  --data '{"status":"ACTIVE"}' > "$TMP_DIR/approve.status"
[ "$(cat "$TMP_DIR/approve.status")" = "200" ]

curl -sS -o "$CREATE_RESP" -w '%{http_code}' -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${SELLER_TOKEN}" \
  --data "{\"title\":\"Already Active Product ${CASE_SUFFIX}\",\"description\":\"Visible product\",\"category\":\"CLOTHING\",\"price_cents\":1999,\"stock_qty\":3,\"photos\":[]}" > "$TMP_DIR/create.status"
[ "$(cat "$TMP_DIR/create.status")" = "201" ]
PRODUCT_ID="$(jq -r '.id' "$CREATE_RESP")"
VISIBILITY_BEFORE="$(psql "$DATABASE_URL" -At -c "SELECT visible FROM \"Product\" WHERE id='${PRODUCT_ID}';")"
[ "$VISIBILITY_BEFORE" = "t" ]

# When
curl -sS -o "$RESP_FILE" -w '%{http_code}' -X PUT "$BASE_URL/admin/sellers/${SELLER_ID}" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  --data '{"status":"ACTIVE"}' > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
jq -e --arg id "$SELLER_ID" '.id == $id and .status == "ACTIVE"' "$RESP_FILE" >/dev/null
DB_STATUS="$(psql "$DATABASE_URL" -At -c "SELECT status FROM \"User\" WHERE id='${USER_ID}';")"
[ "$DB_STATUS" = "ACTIVE" ]
VISIBILITY_AFTER="$(psql "$DATABASE_URL" -At -c "SELECT visible FROM \"Product\" WHERE id='${PRODUCT_ID}';")"
[ "$VISIBILITY_AFTER" = "t" ]
echo "CODEVALID_TEST_ASSERTION_OK:activate_already_active_seller"

# Cleanup
# handled by trap
