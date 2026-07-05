#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_EMAIL="admin-count-${CASE_SUFFIX}@example.com"
MANY_EMAIL="many-${CASE_SUFFIX}@store.com"
ONE_EMAIL="one-${CASE_SUFFIX}@store.com"
ZERO_EMAIL="zero-${CASE_SUFFIX}@store.com"
TMP_DIR="$(mktemp -d)"
cleanup() {
  psql "$DATABASE_URL" -c "DELETE FROM \"Product\" WHERE title LIKE '%${CASE_SUFFIX}%';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email IN ('$MANY_EMAIL','$ONE_EMAIL','$ZERO_EMAIL','$ADMIN_EMAIL'));" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE email IN ('$MANY_EMAIL','$ONE_EMAIL','$ZERO_EMAIL','$ADMIN_EMAIL');" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

register_seller() {
  email="$1"
  store="$2"
  out_json="$3"
  out_status="$4"
  curl -sS -o "$out_json" -w '%{http_code}' -X POST "$BASE_URL/auth/register" -H 'Content-Type: application/json' \
    --data "{\"email\":\"${email}\",\"password\":\"SellerPass123!\",\"role\":\"SELLER\",\"storeName\":\"${store}\",\"bio\":\"bio ${CASE_SUFFIX}\"}" > "$out_status"
  [ "$(cat "$out_status")" = "201" ]
}

create_product() {
  token="$1"
  title="$2"
  out_status="$3"
  curl -sS -o "$TMP_DIR/product.json" -w '%{http_code}' -X POST "$BASE_URL/products" \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer ${token}" \
    --data "{\"title\":\"${title}\",\"description\":\"desc ${CASE_SUFFIX}\",\"category\":\"crafts\",\"price_cents\":1500,\"stock_qty\":4,\"photos\":[\"https://example.com/${CASE_SUFFIX}.jpg\"]}" > "$out_status"
  [ "$(cat "$out_status")" = "201" ]
}

# Given
curl -sS -o "$TMP_DIR/admin.json" -w '%{http_code}' -X POST "$BASE_URL/auth/register" -H 'Content-Type: application/json' \
  --data "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"AdminPass123!\",\"role\":\"ADMIN\"}" > "$TMP_DIR/admin.status"
[ "$(cat "$TMP_DIR/admin.status")" = "201" ]
ADMIN_TOKEN="$(jq -r '.token' "$TMP_DIR/admin.json")"
[ "$ADMIN_TOKEN" != "null" ]

register_seller "$MANY_EMAIL" "Many Store" "$TMP_DIR/many.json" "$TMP_DIR/many.status"
register_seller "$ONE_EMAIL" "One Store" "$TMP_DIR/one.json" "$TMP_DIR/one.status"
register_seller "$ZERO_EMAIL" "Zero Store" "$TMP_DIR/zero.json" "$TMP_DIR/zero.status"

MANY_TOKEN="$(jq -r '.token' "$TMP_DIR/many.json")"
ONE_TOKEN="$(jq -r '.token' "$TMP_DIR/one.json")"
ZERO_TOKEN="$(jq -r '.token' "$TMP_DIR/zero.json")"
[ "$MANY_TOKEN" != "null" ]
[ "$ONE_TOKEN" != "null" ]
[ "$ZERO_TOKEN" != "null" ]

psql "$DATABASE_URL" -c "UPDATE \"User\" SET status='ACTIVE' WHERE email IN ('${MANY_EMAIL}','${ONE_EMAIL}','${ZERO_EMAIL}');" >/dev/null

create_product "$MANY_TOKEN" "Many A ${CASE_SUFFIX}" "$TMP_DIR/p1.status"
create_product "$MANY_TOKEN" "Many B ${CASE_SUFFIX}" "$TMP_DIR/p2.status"
create_product "$MANY_TOKEN" "Many C ${CASE_SUFFIX}" "$TMP_DIR/p3.status"
create_product "$MANY_TOKEN" "Many D ${CASE_SUFFIX}" "$TMP_DIR/p4.status"
create_product "$MANY_TOKEN" "Many E ${CASE_SUFFIX}" "$TMP_DIR/p5.status"
create_product "$ONE_TOKEN" "One Only ${CASE_SUFFIX}" "$TMP_DIR/p6.status"

# When
curl -sS -o "$TMP_DIR/list.json" -w '%{http_code}' "$BASE_URL/admin/sellers" -H "Authorization: Bearer ${ADMIN_TOKEN}" > "$TMP_DIR/list.status"

# Then
[ "$(cat "$TMP_DIR/list.status")" = "200" ]
jq -e --arg e "$MANY_EMAIL" '.[] | select(.email == $e and .product_count == 5)' "$TMP_DIR/list.json" >/dev/null
jq -e --arg e "$ONE_EMAIL" '.[] | select(.email == $e and .product_count == 1)' "$TMP_DIR/list.json" >/dev/null
jq -e --arg e "$ZERO_EMAIL" '.[] | select(.email == $e and .product_count == 0)' "$TMP_DIR/list.json" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:product_count_accurately_reflected_per_seller"

# Cleanup
# handled by trap
