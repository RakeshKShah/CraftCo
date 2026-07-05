#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_EMAIL="reactivate-admin-${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD='AdminPass123!'
SELLER_EMAIL="reactivate-seller-${CASE_SUFFIX}@example.com"
SELLER_PASSWORD='SellerPass123!'
TMP_DIR="$(mktemp -d)"
ADMIN_RESP="$TMP_DIR/admin.json"
SELLER_RESP="$TMP_DIR/seller.json"
CREATE1_RESP="$TMP_DIR/create1.json"
CREATE2_RESP="$TMP_DIR/create2.json"
SUSPEND_RESP="$TMP_DIR/suspend.json"
REACTIVATE_RESP="$TMP_DIR/reactivate.json"
REACTIVATE_STATUS="$TMP_DIR/reactivate.status"
BUYER_LIST_RESP="$TMP_DIR/buyer.json"
BUYER_LIST_STATUS="$TMP_DIR/buyer.status"
cleanup() {
  SELLER_ID="$(jq -r '.user.sellerProfile.id // empty' "$SELLER_RESP" 2>/dev/null || true)"
  USER_ID="$(jq -r '.user.id // empty' "$SELLER_RESP" 2>/dev/null || true)"
  for f in "$CREATE1_RESP" "$CREATE2_RESP"; do
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
  --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"Reactivate Store ${CASE_SUFFIX}\",\"bio\":\"Reactivate bio\"}" > "$TMP_DIR/seller.status"
[ "$(cat "$TMP_DIR/seller.status")" = "201" ]
SELLER_TOKEN="$(jq -r '.token' "$SELLER_RESP")"
SELLER_ID="$(jq -r '.user.sellerProfile.id' "$SELLER_RESP")"
USER_ID="$(jq -r '.user.id' "$SELLER_RESP")"

curl -sS -o "$TMP_DIR/approve.json" -w '%{http_code}' -X PUT "$BASE_URL/admin/sellers/${SELLER_ID}" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  --data '{"status":"ACTIVE"}' > "$TMP_DIR/approve.status"
[ "$(cat "$TMP_DIR/approve.status")" = "200" ]

for idx in 1 2; do
  out="$TMP_DIR/create${idx}.json"
  status="$TMP_DIR/create${idx}.status"
  curl -sS -o "$out" -w '%{http_code}' -X POST "$BASE_URL/products" \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer ${SELLER_TOKEN}" \
    --data "{\"title\":\"Reactivate Product ${idx} ${CASE_SUFFIX}\",\"description\":\"Product ${idx}\",\"category\":\"CLOTHING\",\"price_cents\":$((2000+idx)),\"stock_qty\":4,\"photos\":[]}" > "$status"
  [ "$(cat "$status")" = "201" ]
done
cp "$TMP_DIR/create1.json" "$CREATE1_RESP"
cp "$TMP_DIR/create2.json" "$CREATE2_RESP"

curl -sS -o "$SUSPEND_RESP" -w '%{http_code}' -X PUT "$BASE_URL/admin/sellers/${SELLER_ID}" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  --data '{"status":"SUSPENDED"}' > "$TMP_DIR/suspend.status"
[ "$(cat "$TMP_DIR/suspend.status")" = "200" ]
PRECHECK_HIDDEN="$(psql "$DATABASE_URL" -At -c "SELECT COUNT(*) FROM \"Product\" WHERE \"sellerId\"='${SELLER_ID}' AND visible=false;")"
[ "$PRECHECK_HIDDEN" = "2" ]

# When
curl -sS -o "$REACTIVATE_RESP" -w '%{http_code}' -X PUT "$BASE_URL/admin/sellers/${SELLER_ID}" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  --data '{"status":"ACTIVE"}' > "$REACTIVATE_STATUS"

curl -sS -o "$BUYER_LIST_RESP" -w '%{http_code}' "$BASE_URL/products" > "$BUYER_LIST_STATUS"

# Then
[ "$(cat "$REACTIVATE_STATUS")" = "200" ]
jq -e --arg id "$SELLER_ID" '.id == $id and .status == "ACTIVE"' "$REACTIVATE_RESP" >/dev/null
DB_STATUS="$(psql "$DATABASE_URL" -At -c "SELECT status FROM \"User\" WHERE id='${USER_ID}';")"
[ "$DB_STATUS" = "ACTIVE" ]
VISIBLE_TRUE_COUNT="$(psql "$DATABASE_URL" -At -c "SELECT COUNT(*) FROM \"Product\" WHERE \"sellerId\"='${SELLER_ID}' AND visible=true;")"
[ "$VISIBLE_TRUE_COUNT" = "2" ]
[ "$(cat "$BUYER_LIST_STATUS")" = "200" ]
jq -e --arg sid "$SELLER_ID" '[.[] | select(.sellerId == $sid)] | length == 2' "$BUYER_LIST_RESP" >/dev/null
echo "CODEVALID_TEST_ASSERTION_OK:reactivate_seller_restores_product_visibility"

# Cleanup
# handled by trap
