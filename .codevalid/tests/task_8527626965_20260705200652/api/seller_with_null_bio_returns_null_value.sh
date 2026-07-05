#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_EMAIL="admin-bio-${CASE_SUFFIX}@example.com"
NO_BIO_EMAIL="nobio-${CASE_SUFFIX}@store.com"
WITH_BIO_EMAIL="withbio-${CASE_SUFFIX}@store.com"
TMP_DIR="$(mktemp -d)"
cleanup() {
  psql "$DATABASE_URL" -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email IN ('$NO_BIO_EMAIL','$WITH_BIO_EMAIL','$ADMIN_EMAIL'));" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE email IN ('$NO_BIO_EMAIL','$WITH_BIO_EMAIL','$ADMIN_EMAIL');" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Given
curl -sS -o "$TMP_DIR/admin.json" -w '%{http_code}' -X POST "$BASE_URL/auth/register" -H 'Content-Type: application/json' \
  --data "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"AdminPass123!\",\"role\":\"ADMIN\"}" > "$TMP_DIR/admin.status"
[ "$(cat "$TMP_DIR/admin.status")" = "201" ]
ADMIN_TOKEN="$(jq -r '.token' "$TMP_DIR/admin.json")"
[ "$ADMIN_TOKEN" != "null" ]

curl -sS -o "$TMP_DIR/nobio.json" -w '%{http_code}' -X POST "$BASE_URL/auth/register" -H 'Content-Type: application/json' \
  --data "{\"email\":\"${NO_BIO_EMAIL}\",\"password\":\"SellerPass123!\",\"role\":\"SELLER\",\"storeName\":\"Empty Bio Store ${CASE_SUFFIX}\"}" > "$TMP_DIR/nobio.status"
[ "$(cat "$TMP_DIR/nobio.status")" = "201" ]

curl -sS -o "$TMP_DIR/withbio.json" -w '%{http_code}' -X POST "$BASE_URL/auth/register" -H 'Content-Type: application/json' \
  --data "{\"email\":\"${WITH_BIO_EMAIL}\",\"password\":\"SellerPass123!\",\"role\":\"SELLER\",\"storeName\":\"Full Bio Store ${CASE_SUFFIX}\",\"bio\":\"We sell quality goods\"}" > "$TMP_DIR/withbio.status"
[ "$(cat "$TMP_DIR/withbio.status")" = "201" ]

psql "$DATABASE_URL" -c "UPDATE \"SellerProfile\" SET bio = NULL WHERE \"userId\" = (SELECT id FROM \"User\" WHERE email='${NO_BIO_EMAIL}');" >/dev/null

# When
curl -sS -o "$TMP_DIR/list.json" -w '%{http_code}' "$BASE_URL/admin/sellers" -H "Authorization: Bearer ${ADMIN_TOKEN}" > "$TMP_DIR/list.status"

# Then
[ "$(cat "$TMP_DIR/list.status")" = "200" ]
jq -e --arg e "$NO_BIO_EMAIL" '.[] | select(.email == $e and .bio == null)' "$TMP_DIR/list.json" >/dev/null
jq -e --arg e "$WITH_BIO_EMAIL" '.[] | select(.email == $e and .bio == "We sell quality goods")' "$TMP_DIR/list.json" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:seller_with_null_bio_returns_null_value"

# Cleanup
# handled by trap
