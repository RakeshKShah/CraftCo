#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_EMAIL="suspend-admin-${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD='AdminPass123!'
SELLER_EMAIL="suspend-seller-${CASE_SUFFIX}@example.com"
SELLER_PASSWORD='SellerPass123!'
TMP_DIR="$(mktemp -d)"
ADMIN_RESP="$TMP_DIR/admin.json"
SELLER_RESP="$TMP_DIR/seller.json"
APPROVE_RESP="$TMP_DIR/approve.json"
APPROVE_STATUS="$TMP_DIR/approve.status"
CREATE1_RESP="$TMP_DIR/create1.json"
CREATE1_STATUS="$TMP_DIR/create1.status"
CREATE2_RESP="$TMP_DIR/create2.json"
CREATE2_STATUS="$TMP_DIR/create2.status"
CREATE3_RESP="$TMP_DIR/create3.json"
CREATE3_STATUS="$TMP_DIR/create3.status"
SUSPEND_RESP="$TMP_DIR/suspend.json"
SUSPEND_STATUS="$TMP_DIR/suspend.status"
BUYER_LIST_RESP="$TMP_DIR/buyer-products.json"
BUYER_LIST_STATUS="$TMP_DIR/buyer-products.status"
ADMIN_LIST_RESP="$TMP_DIR/admin-sellers.json"
ADMIN_LIST_STATUS="$TMP_DIR/admin-sellers.status"
cleanup() {
  SELLER_ID="$(jq -r '.user.sellerProfile.id // empty' "$SELLER_RESP" 2>/dev/null || true)"
  USER_ID="$(jq -r '.user.id // empty' "$SELLER_RESP" 2>/dev/null || true)"
  for f in "$CREATE1_RESP" "$CREATE2_RESP" "$CREATE3_RESP"; do
    PRODUCT_ID="$(jq -r '.id // empty' "$f" 2>/dev/null || true)"
    [ -n "$PRODUCT_ID" ] && psql "$DATABASE_URL" -c "DELETE FROM \"Product\" WHERE id='${PRODUCT_ID}';" >/dev/null 2>&1 || true
  done
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
  --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"Suspend Store ${CASE_SUFFIX}\",\"bio\":\"Suspend bio\"}" > "$TMP_DIR/seller.status"
[ "$(cat "$TMP_DIR/seller.status")" = "201" ]
SELLER_TOKEN="$(jq -r '.token' "$SELLER_RESP")"
SELLER_ID="$(jq -r '.user.sellerProfile.id' "$SELLER_RESP")"
USER_ID="$(jq -r '.user.id' "$SELLER_RESP")"

curl -sS -o "$APPROVE_RESP" -w '%{http_code}' -X PUT "$BASE_URL/admin/sellers/${SELLER_ID}" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  --data '{"status":"ACTIVE"}' > "$APPROVE_STATUS"
[ "$(cat "$APPROVE_STATUS")" = "200" ]

for idx in 1 2 3; do
  resp_var="CREATE${idx}_RESP"
  status_var="CREATE${idx}_STATUS"
  title="Suspend Product ${idx} ${CASE_SUFFIX}"
  eval "resp_path=\${$resp_var}"
  eval "status_path=\${$status_var}"
  curl -sS -o "$resp_path" -w '%{http_code}' -X POST "$BASE_URL/products" \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer ${SELLER_TOKEN}" \
    --data "{\"title\":\"${title}\",\"description\":\"Product ${idx}\",\"category\":\"CLOTHING\",\"price_cents\":$((1000+idx)),\"stock_qty\":5,\"photos\":[]}" > "$status_path"
  [ "$(cat "$status_path")" = "201" ]
done

# When
curl -sS -o "$SUSPEND_RESP" -w '%{http_code}' -X PUT "$BASE_URL/admin/sellers/${SELLER_ID}" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  --data '{"status":"SUSPENDED"}' > "$SUSPEND_STATUS"

curl -sS -o "$BUYER_LIST_RESP" -w '%{http_code}' "$BASE_URL/products" > "$BUYER_LIST_STATUS"

curl -sS -o "$ADMIN_LIST_RESP" -w '%{http_code}' "$BASE_URL/admin/sellers" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" > "$ADMIN_LIST_STATUS"

# Then
[ "$(cat "$SUSPEND_STATUS")" = "200" ]
jq -e --arg id "$SELLER_ID" '.id == $id and .status == "SUSPENDED"' "$SUSPEND_RESP" >/dev/null
DB_STATUS="$(psql "$DATABASE_URL" -At -c "SELECT status FROM \"User\" WHERE id='${USER_ID}';")"
[ "$DB_STATUS" = "SUSPENDED" ]
VISIBLE_FALSE_COUNT="$(psql "$DATABASE_URL" -At -c "SELECT COUNT(*) FROM \"Product\" WHERE \"sellerId\"='${SELLER_ID}' AND visible=false;")"
[ "$VISIBLE_FALSE_COUNT" = "3" ]
[ "$(cat "$BUYER_LIST_STATUS")" = "200" ]
jq -e --arg sid "$SELLER_ID" '[.[] | select(.sellerId == $sid)] | length == 0' "$BUYER_LIST_RESP" >/dev/null
[ "$(cat "$ADMIN_LIST_STATUS")" = "200" ]
jq -e --arg e "$SELLER_EMAIL" '.[] | select(.email == $e and .status == "SUSPENDED" and .product_count == 3)' "$ADMIN_LIST_RESP" >/dev/null
echo "CODEVALID_TEST_ASSERTION_OK:suspend_seller_hides_products"

# Cleanup
# handled by trap
