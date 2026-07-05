#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_EMAIL="seller-not-found-admin-${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD='AdminPass123!'
MISSING_SELLER_ID="nonexistent-seller-${CASE_SUFFIX}"
TMP_DIR="$(mktemp -d)"
ADMIN_RESP="$TMP_DIR/admin.json"
RESP_FILE="$TMP_DIR/not-found.json"
STATUS_FILE="$TMP_DIR/not-found.status"
cleanup() {
  psql "$DATABASE_URL" -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email='${ADMIN_EMAIL}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE email='${ADMIN_EMAIL}';" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Given
EXISTS_BEFORE="$(psql "$DATABASE_URL" -At -c "SELECT COUNT(*) FROM \"SellerProfile\" WHERE id='${MISSING_SELLER_ID}';")"
[ "$EXISTS_BEFORE" = "0" ]
curl -sS -o "$ADMIN_RESP" -w '%{http_code}' -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\",\"role\":\"ADMIN\"}" > "$TMP_DIR/admin.status"
[ "$(cat "$TMP_DIR/admin.status")" = "201" ]
ADMIN_TOKEN="$(jq -r '.token' "$ADMIN_RESP")"

# When
curl -sS -o "$RESP_FILE" -w '%{http_code}' -X PUT "$BASE_URL/admin/sellers/${MISSING_SELLER_ID}" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  --data '{"status":"SUSPENDED"}' > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "404" ]
grep -F '"error":"Seller not found"' "$RESP_FILE" >/dev/null
echo "CODEVALID_TEST_ASSERTION_OK:seller_not_found_returns_404"

# Cleanup
# handled by trap
