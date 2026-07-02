#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_EMAIL="admin-removed-${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD="AdminPass123!"
SELLER_USER_ID="removed-check-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="removed-check-profile-${CASE_SUFFIX}"
PROD1_ID="prod-001-${CASE_SUFFIX}"
PROD2_ID="prod-002-${CASE_SUFFIX}"
REGISTER_RESPONSE="/tmp/removed_status_products_excluded_register_${CASE_SUFFIX}.json"
REGISTER_STATUS="/tmp/removed_status_products_excluded_register_${CASE_SUFFIX}.status"
RESPONSE_FILE="/tmp/removed_status_products_excluded_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/removed_status_products_excluded_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$REGISTER_RESPONSE" "$REGISTER_STATUS" "$RESPONSE_FILE" "$STATUS_FILE"; }
cleanup_db() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id IN ('${PROD1_ID}','${PROD2_ID}'); DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}'; DELETE FROM users WHERE email = '${ADMIN_EMAIL}' OR id = '${SELLER_USER_ID}';" >/dev/null 2>&1 || true
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
VALUES ('${SELLER_USER_ID}', 'removed-products-${CASE_SUFFIX}@example.com', 'x', 'SELLER', 'ACTIVE', TIMESTAMP '2024-08-01 00:00:00');
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Removed Check Shop ${CASE_SUFFIX}', 'bio');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD1_ID}', '${SELLER_PROFILE_ID}', 'Active Product ${CASE_SUFFIX}', 'included', 'ELECTRONICS', 8100, 1, '[]', 'ACTIVE', true, TIMESTAMP '2024-08-10 00:00:00'),
  ('${PROD2_ID}', '${SELLER_PROFILE_ID}', 'Removed Product ${CASE_SUFFIX}', 'excluded', 'ELECTRONICS', 8200, 1, '[]', 'REMOVED', true, TIMESTAMP '2024-08-09 00:00:00');
" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
jq -e 'type == "array"' "$RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"$PROD1_ID"'")) | length == 1' "$RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"$PROD2_ID"'")) | length == 0' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:removed_status_products_excluded"

# Cleanup
:
