#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_EMAIL="admin-order-${CASE_SUFFIX}@example.com"
OLD_EMAIL="old-${CASE_SUFFIX}@example.com"
MID_EMAIL="mid-${CASE_SUFFIX}@example.com"
NEW_EMAIL="new-${CASE_SUFFIX}@example.com"
TMP_DIR="$(mktemp -d)"
cleanup() {
  psql "$DATABASE_URL" -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email IN ('$OLD_EMAIL','$MID_EMAIL','$NEW_EMAIL','$ADMIN_EMAIL'));" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -c "DELETE FROM \"User\" WHERE email IN ('$OLD_EMAIL','$MID_EMAIL','$NEW_EMAIL','$ADMIN_EMAIL');" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Given
curl -sS -o "$TMP_DIR/admin.json" -w '%{http_code}' -X POST "$BASE_URL/auth/register" -H 'Content-Type: application/json' \
  --data "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"AdminPass123!\",\"role\":\"ADMIN\"}" > "$TMP_DIR/admin.status"
[ "$(cat "$TMP_DIR/admin.status")" = "201" ]
ADMIN_TOKEN="$(jq -r '.token' "$TMP_DIR/admin.json")"
[ "$ADMIN_TOKEN" != "null" ]

curl -sS -o "$TMP_DIR/old.json" -w '%{http_code}' -X POST "$BASE_URL/auth/register" -H 'Content-Type: application/json' --data "{\"email\":\"${OLD_EMAIL}\",\"password\":\"SellerPass123!\",\"role\":\"SELLER\",\"storeName\":\"Old Store\",\"bio\":\"old\"}" > "$TMP_DIR/old.status"
[ "$(cat "$TMP_DIR/old.status")" = "201" ]
curl -sS -o "$TMP_DIR/mid.json" -w '%{http_code}' -X POST "$BASE_URL/auth/register" -H 'Content-Type: application/json' --data "{\"email\":\"${MID_EMAIL}\",\"password\":\"SellerPass123!\",\"role\":\"SELLER\",\"storeName\":\"Mid Store\",\"bio\":\"mid\"}" > "$TMP_DIR/mid.status"
[ "$(cat "$TMP_DIR/mid.status")" = "201" ]
curl -sS -o "$TMP_DIR/new.json" -w '%{http_code}' -X POST "$BASE_URL/auth/register" -H 'Content-Type: application/json' --data "{\"email\":\"${NEW_EMAIL}\",\"password\":\"SellerPass123!\",\"role\":\"SELLER\",\"storeName\":\"New Store\",\"bio\":\"new\"}" > "$TMP_DIR/new.status"
[ "$(cat "$TMP_DIR/new.status")" = "201" ]

psql "$DATABASE_URL" -c "UPDATE \"User\" SET \"createdAt\"='2024-01-15T10:00:00Z' WHERE email='${OLD_EMAIL}';" >/dev/null
psql "$DATABASE_URL" -c "UPDATE \"User\" SET \"createdAt\"='2024-01-18T09:15:00Z' WHERE email='${MID_EMAIL}';" >/dev/null
psql "$DATABASE_URL" -c "UPDATE \"User\" SET \"createdAt\"='2024-01-20T14:30:00Z' WHERE email='${NEW_EMAIL}';" >/dev/null

# When
curl -sS -o "$TMP_DIR/list.json" -w '%{http_code}' "$BASE_URL/admin/sellers" -H "Authorization: Bearer ${ADMIN_TOKEN}" > "$TMP_DIR/list.status"

# Then
[ "$(cat "$TMP_DIR/list.status")" = "200" ]
ORDERED_EMAILS="$(jq -r --arg old "$OLD_EMAIL" --arg mid "$MID_EMAIL" --arg new "$NEW_EMAIL" '[.[] | select(.email == $old or .email == $mid or .email == $new) | .email] | join(",")' "$TMP_DIR/list.json")"
[ "$ORDERED_EMAILS" = "$NEW_EMAIL,$MID_EMAIL,$OLD_EMAIL" ]
jq -e --arg e "$NEW_EMAIL" '.[] | select(.email == $e) | (.created_at | startswith("2024-01-20T14:30:00"))' "$TMP_DIR/list.json" >/dev/null
jq -e --arg e "$MID_EMAIL" '.[] | select(.email == $e) | (.created_at | startswith("2024-01-18T09:15:00"))' "$TMP_DIR/list.json" >/dev/null
jq -e --arg e "$OLD_EMAIL" '.[] | select(.email == $e) | (.created_at | startswith("2024-01-15T10:00:00"))' "$TMP_DIR/list.json" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:sellers_ordered_by_creation_date_descending"

# Cleanup
# handled by trap
