#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_EMAIL="admin-status-${CASE_SUFFIX}@example.com"
PENDING_EMAIL="pending-${CASE_SUFFIX}@store.com"
ACTIVE_EMAIL="active-${CASE_SUFFIX}@store.com"
SUSPENDED_EMAIL="suspended-${CASE_SUFFIX}@store.com"
TMP_DIR="$(mktemp -d)"
cleanup() {
  psql "$DATABASE_URL" -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email IN ('$PENDING_EMAIL','$ACTIVE_EMAIL','$SUSPENDED_EMAIL','$ADMIN_EMAIL'));" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE email IN ('$PENDING_EMAIL','$ACTIVE_EMAIL','$SUSPENDED_EMAIL','$ADMIN_EMAIL');" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Given
curl -sS -o "$TMP_DIR/admin.json" -w '%{http_code}' -X POST "$BASE_URL/auth/register" -H 'Content-Type: application/json' \
  --data "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"AdminPass123!\",\"role\":\"ADMIN\"}" > "$TMP_DIR/admin.status"
[ "$(cat "$TMP_DIR/admin.status")" = "201" ]
ADMIN_TOKEN="$(jq -r '.token' "$TMP_DIR/admin.json")"
[ "$ADMIN_TOKEN" != "null" ]

curl -sS -o "$TMP_DIR/pending.json" -w '%{http_code}' -X POST "$BASE_URL/auth/register" -H 'Content-Type: application/json' --data "{\"email\":\"${PENDING_EMAIL}\",\"password\":\"SellerPass123!\",\"role\":\"SELLER\",\"storeName\":\"Pending Store\",\"bio\":\"pending bio\"}" > "$TMP_DIR/pending.status"
[ "$(cat "$TMP_DIR/pending.status")" = "201" ]
curl -sS -o "$TMP_DIR/active.json" -w '%{http_code}' -X POST "$BASE_URL/auth/register" -H 'Content-Type: application/json' --data "{\"email\":\"${ACTIVE_EMAIL}\",\"password\":\"SellerPass123!\",\"role\":\"SELLER\",\"storeName\":\"Active Store\",\"bio\":\"active bio\"}" > "$TMP_DIR/active.status"
[ "$(cat "$TMP_DIR/active.status")" = "201" ]
curl -sS -o "$TMP_DIR/suspended.json" -w '%{http_code}' -X POST "$BASE_URL/auth/register" -H 'Content-Type: application/json' --data "{\"email\":\"${SUSPENDED_EMAIL}\",\"password\":\"SellerPass123!\",\"role\":\"SELLER\",\"storeName\":\"Suspended Store\",\"bio\":\"suspended bio\"}" > "$TMP_DIR/suspended.status"
[ "$(cat "$TMP_DIR/suspended.status")" = "201" ]

psql "$DATABASE_URL" -c "UPDATE \"User\" SET status='ACTIVE' WHERE email='${ACTIVE_EMAIL}';" >/dev/null
psql "$DATABASE_URL" -c "UPDATE \"User\" SET status='SUSPENDED' WHERE email='${SUSPENDED_EMAIL}';" >/dev/null

# When
curl -sS -o "$TMP_DIR/list.json" -w '%{http_code}' "$BASE_URL/admin/sellers" -H "Authorization: Bearer ${ADMIN_TOKEN}" > "$TMP_DIR/list.status"

# Then
[ "$(cat "$TMP_DIR/list.status")" = "200" ]
jq -e --arg e "$PENDING_EMAIL" '.[] | select(.email == $e and .status == "PENDING")' "$TMP_DIR/list.json" >/dev/null
jq -e --arg e "$ACTIVE_EMAIL" '.[] | select(.email == $e and .status == "ACTIVE")' "$TMP_DIR/list.json" >/dev/null
jq -e --arg e "$SUSPENDED_EMAIL" '.[] | select(.email == $e and .status == "SUSPENDED")' "$TMP_DIR/list.json" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:admin_views_sellers_with_various_statuses"

# Cleanup
# handled by trap
