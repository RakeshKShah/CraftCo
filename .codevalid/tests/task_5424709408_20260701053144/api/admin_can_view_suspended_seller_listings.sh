#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_EMAIL="admin-view-suspended-${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD="AdminPass123!"
SELLER_USER_ID="admin-suspended-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="admin-suspended-profile-${CASE_SUFFIX}"
PROD1_ID="prod-001-${CASE_SUFFIX}"
REGISTER_RESPONSE="/tmp/admin_can_view_suspended_seller_listings_register_${CASE_SUFFIX}.json"
REGISTER_STATUS="/tmp/admin_can_view_suspended_seller_listings_register_${CASE_SUFFIX}.status"
RESPONSE_FILE="/tmp/admin_can_view_suspended_seller_listings_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/admin_can_view_suspended_seller_listings_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$REGISTER_RESPONSE" "$REGISTER_STATUS" "$RESPONSE_FILE" "$STATUS_FILE"; }
cleanup_db() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id = '${PROD1_ID}'; DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}'; DELETE FROM users WHERE email = '${ADMIN_EMAIL}' OR id = '${SELLER_USER_ID}';" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
curl -sS -o "$REGISTER_RESPONSE" -w '%{http_code}' -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\",\"role\":\"ADMIN\"}" > "$REGISTER_STATUS"
[ "$(cat "$REGISTER_STATUS")" = "201" ]
ADMIN_TOKEN="$(jq -r '.token' "$REGISTER_RESPONSE")"
[ "$ADMIN_TOKEN" != "null" ]

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', 'suspended-view-${CASE_SUFFIX}@example.com', 'x', 'SELLER', 'SUSPENDED', TIMESTAMP '2024-04-01 00:00:00');
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Suspended Shop ${CASE_SUFFIX}', 'bio');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES ('${PROD1_ID}', '${SELLER_PROFILE_ID}', 'Suspended Listing ${CASE_SUFFIX}', 'still visible to admin', 'ELECTRONICS', 4100, 6, '[]', 'ACTIVE', false, TIMESTAMP '2024-04-10 00:00:00');
" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
jq -e 'type == "array"' "$RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"$PROD1_ID"'")) | length == 1' "$RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"$PROD1_ID"'"))[0].seller != null' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:admin_can_view_suspended_seller_listings"

# Cleanup
:
