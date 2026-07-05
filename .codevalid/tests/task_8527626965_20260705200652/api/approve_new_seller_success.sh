#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_EMAIL="approve-admin-${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD='AdminPass123!'
SELLER_EMAIL="approve-seller-${CASE_SUFFIX}@example.com"
SELLER_PASSWORD='SellerPass123!'
PRODUCT_TITLE="Approved Product ${CASE_SUFFIX}"
TMP_DIR="$(mktemp -d)"
ADMIN_RESP="$TMP_DIR/admin-register.json"
ADMIN_STATUS="$TMP_DIR/admin-register.status"
SELLER_RESP="$TMP_DIR/seller-register.json"
SELLER_STATUS="$TMP_DIR/seller-register.status"
APPROVE_RESP="$TMP_DIR/approve.json"
APPROVE_STATUS="$TMP_DIR/approve.status"
CREATE_RESP="$TMP_DIR/create.json"
CREATE_STATUS="$TMP_DIR/create.status"
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
  --data "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\",\"role\":\"ADMIN\"}" > "$ADMIN_STATUS"
[ "$(cat "$ADMIN_STATUS")" = "201" ]
ADMIN_TOKEN="$(jq -r '.token' "$ADMIN_RESP")"
[ -n "$ADMIN_TOKEN" ] && [ "$ADMIN_TOKEN" != "null" ]

curl -sS -o "$SELLER_RESP" -w '%{http_code}' -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"Approve Store ${CASE_SUFFIX}\",\"bio\":\"Approval bio ${CASE_SUFFIX}\"}" > "$SELLER_STATUS"
[ "$(cat "$SELLER_STATUS")" = "201" ]
SELLER_TOKEN="$(jq -r '.token' "$SELLER_RESP")"
SELLER_ID="$(jq -r '.user.sellerProfile.id' "$SELLER_RESP")"
USER_ID="$(jq -r '.user.id' "$SELLER_RESP")"
[ -n "$SELLER_ID" ] && [ "$SELLER_ID" != "null" ]
[ "$(jq -r '.user.status' "$SELLER_RESP")" = "PENDING" ]

# When
curl -sS -o "$APPROVE_RESP" -w '%{http_code}' -X PUT "$BASE_URL/admin/sellers/${SELLER_ID}" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  --data '{"status":"ACTIVE"}' > "$APPROVE_STATUS"

curl -sS -o "$CREATE_RESP" -w '%{http_code}' -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${SELLER_TOKEN}" \
  --data "{\"title\":\"${PRODUCT_TITLE}\",\"description\":\"Approved seller listing\",\"category\":\"CLOTHING\",\"price_cents\":1200,\"stock_qty\":2,\"photos\":[]}" > "$CREATE_STATUS"

# Then
[ "$(cat "$APPROVE_STATUS")" = "200" ]
jq -e --arg id "$SELLER_ID" '.id == $id and .status == "ACTIVE"' "$APPROVE_RESP" >/dev/null
DB_STATUS="$(psql "$DATABASE_URL" -At -c "SELECT status FROM \"User\" WHERE id='${USER_ID}';")"
[ "$DB_STATUS" = "ACTIVE" ]
[ "$(cat "$CREATE_STATUS")" = "201" ]
grep -F "\"title\":\"${PRODUCT_TITLE}\"" "$CREATE_RESP" >/dev/null
PRODUCT_COUNT="$(psql "$DATABASE_URL" -At -c "SELECT COUNT(*) FROM \"Product\" WHERE \"sellerId\"='${SELLER_ID}';")"
[ "$PRODUCT_COUNT" = "1" ]
echo "CODEVALID_TEST_ASSERTION_OK:approve_new_seller_success"

# Cleanup
# handled by trap
