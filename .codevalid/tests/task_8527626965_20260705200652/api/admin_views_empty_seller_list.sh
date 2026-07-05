#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_EMAIL="admin-empty-${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD='AdminPass123!'
TMP_DIR="$(mktemp -d)"
ADMIN_RESP="$TMP_DIR/admin-register.json"
ADMIN_STATUS="$TMP_DIR/admin-register.status"
LIST_RESP="$TMP_DIR/sellers.json"
LIST_STATUS="$TMP_DIR/sellers.status"
cleanup() {
  psql "$DATABASE_URL" -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email='${ADMIN_EMAIL}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE email='${ADMIN_EMAIL}';" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Given
BEFORE_COUNT="$(psql "$DATABASE_URL" -t -A -c 'SELECT COUNT(*) FROM "SellerProfile";')"
[ "$BEFORE_COUNT" = "0" ]

curl -sS -o "$ADMIN_RESP" -w '%{http_code}' -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\",\"role\":\"ADMIN\"}" > "$ADMIN_STATUS"
[ "$(cat "$ADMIN_STATUS")" = "201" ]
ADMIN_TOKEN="$(jq -r '.token' "$ADMIN_RESP")"
[ "$ADMIN_TOKEN" != "null" ]

# When
curl -sS -o "$LIST_RESP" -w '%{http_code}' "$BASE_URL/admin/sellers" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" > "$LIST_STATUS"

# Then
[ "$(cat "$LIST_STATUS")" = "200" ]
jq -e 'type == "array" and length == 0' "$LIST_RESP" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:admin_views_empty_seller_list"

# Cleanup
# handled by trap
