#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_EMAIL="admin-fields-${CASE_SUFFIX}@example.com"
SELLER_EMAIL="complete-${CASE_SUFFIX}@store.com"
TMP_DIR="$(mktemp -d)"
cleanup() {
  psql "$DATABASE_URL" -c "DELETE FROM \"Product\" WHERE title LIKE 'Complete Product %${CASE_SUFFIX}%';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email IN ('$SELLER_EMAIL','$ADMIN_EMAIL'));" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE email IN ('$SELLER_EMAIL','$ADMIN_EMAIL');" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Given
curl -sS -o "$TMP_DIR/admin.json" -w '%{http_code}' -X POST "$BASE_URL/auth/register" -H 'Content-Type: application/json' \
  --data "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"AdminPass123!\",\"role\":\"ADMIN\"}" > "$TMP_DIR/admin.status"
[ "$(cat "$TMP_DIR/admin.status")" = "201" ]
ADMIN_TOKEN="$(jq -r '.token' "$TMP_DIR/admin.json")"
[ "$ADMIN_TOKEN" != "null" ]

curl -sS -o "$TMP_DIR/seller.json" -w '%{http_code}' -X POST "$BASE_URL/auth/register" -H 'Content-Type: application/json' \
  --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"SellerPass123!\",\"role\":\"SELLER\",\"storeName\":\"Complete Store\",\"bio\":\"A complete store\"}" > "$TMP_DIR/seller.status"
[ "$(cat "$TMP_DIR/seller.status")" = "201" ]
SELLER_TOKEN="$(jq -r '.token' "$TMP_DIR/seller.json")"
[ "$SELLER_TOKEN" != "null" ]

psql "$DATABASE_URL" -c "UPDATE \"User\" SET status='ACTIVE' WHERE email='${SELLER_EMAIL}';" >/dev/null

for n in 1 2; do
  curl -sS -o "$TMP_DIR/product-${n}.json" -w '%{http_code}' -X POST "$BASE_URL/products" \
    -H 'Content-Type: application/json' -H "Authorization: Bearer ${SELLER_TOKEN}" \
    --data "{\"title\":\"Complete Product ${n} ${CASE_SUFFIX}\",\"description\":\"desc ${n}\",\"category\":\"art\",\"price_cents\":2000,\"stock_qty\":3,\"photos\":[\"https://example.com/p${n}.jpg\"]}" > "$TMP_DIR/product-${n}.status"
  [ "$(cat "$TMP_DIR/product-${n}.status")" = "201" ]
done

# When
curl -sS -o "$TMP_DIR/list.json" -w '%{http_code}' "$BASE_URL/admin/sellers" -H "Authorization: Bearer ${ADMIN_TOKEN}" > "$TMP_DIR/list.status"

# Then
[ "$(cat "$TMP_DIR/list.status")" = "200" ]
jq -e --arg e "$SELLER_EMAIL" '
  .[] | select(.email == $e)
  | (.id | type == "string")
  and (.user_id | type == "string")
  and (.email | type == "string")
  and (.store_name | type == "string")
  and ((.bio == null) or (.bio | type == "string"))
  and (.status | type == "string")
  and (.product_count | type == "number")
  and (.created_at | type == "string")
' "$TMP_DIR/list.json" >/dev/null
jq -e --arg e "$SELLER_EMAIL" '.[] | select(.email == $e and .product_count == 2 and .store_name == "Complete Store" and .bio == "A complete store")' "$TMP_DIR/list.json" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:response_includes_all_required_fields"

# Cleanup
# handled by trap
