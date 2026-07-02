#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ADMIN_EMAIL="admin-${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD="AdminPass123!"
SELLER1_USER_ID="admin-all-seller1-user-${CASE_SUFFIX}"
SELLER1_PROFILE_ID="admin-all-seller1-profile-${CASE_SUFFIX}"
SELLER2_USER_ID="admin-all-seller2-user-${CASE_SUFFIX}"
SELLER2_PROFILE_ID="admin-all-seller2-profile-${CASE_SUFFIX}"
PROD1_ID="prod-001-${CASE_SUFFIX}"
PROD2_ID="prod-002-${CASE_SUFFIX}"
PROD3_ID="prod-003-${CASE_SUFFIX}"
REGISTER_RESPONSE="/tmp/admin_sees_all_products_including_hidden_register_${CASE_SUFFIX}.json"
REGISTER_STATUS="/tmp/admin_sees_all_products_including_hidden_register_${CASE_SUFFIX}.status"
RESPONSE_FILE="/tmp/admin_sees_all_products_including_hidden_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/admin_sees_all_products_including_hidden_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$REGISTER_RESPONSE" "$REGISTER_STATUS" "$RESPONSE_FILE" "$STATUS_FILE"; }
cleanup_db() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id IN ('${PROD1_ID}','${PROD2_ID}','${PROD3_ID}'); DELETE FROM seller_profiles WHERE id IN ('${SELLER1_PROFILE_ID}','${SELLER2_PROFILE_ID}'); DELETE FROM users WHERE email = '${ADMIN_EMAIL}' OR id IN ('${SELLER1_USER_ID}','${SELLER2_USER_ID}');" >/dev/null 2>&1 || true
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
VALUES
  ('${SELLER1_USER_ID}', 'admin-visible-${CASE_SUFFIX}@example.com', 'x', 'SELLER', 'ACTIVE', TIMESTAMP '2024-02-01 00:00:00'),
  ('${SELLER2_USER_ID}', 'admin-hidden-${CASE_SUFFIX}@example.com', 'x', 'SELLER', 'SUSPENDED', TIMESTAMP '2024-02-01 00:00:01');
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES
  ('${SELLER1_PROFILE_ID}', '${SELLER1_USER_ID}', 'Admin Visible ${CASE_SUFFIX}', 'bio 1'),
  ('${SELLER2_PROFILE_ID}', '${SELLER2_USER_ID}', 'Admin Hidden ${CASE_SUFFIX}', 'bio 2');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD1_ID}', '${SELLER1_PROFILE_ID}', 'Widget A ${CASE_SUFFIX}', 'visible active', 'ELECTRONICS', 2200, 3, '[]', 'ACTIVE', true, TIMESTAMP '2024-02-10 00:00:00'),
  ('${PROD2_ID}', '${SELLER2_PROFILE_ID}', 'Widget B ${CASE_SUFFIX}', 'hidden active', 'ELECTRONICS', 2300, 3, '[]', 'ACTIVE', false, TIMESTAMP '2024-02-09 00:00:00'),
  ('${PROD3_ID}', '${SELLER1_PROFILE_ID}', 'Widget C ${CASE_SUFFIX}', 'removed item', 'ELECTRONICS', 2400, 3, '[]', 'REMOVED', true, TIMESTAMP '2024-02-08 00:00:00');
" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
jq -e 'type == "array"' "$RESPONSE_FILE" >/dev/null
jq -e 'length == 2' "$RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"$PROD1_ID"'")) | length == 1' "$RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"$PROD2_ID"'")) | length == 1' "$RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"$PROD3_ID"'")) | length == 0' "$RESPONSE_FILE" >/dev/null
jq -e 'all(.[]; .seller != null)' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:admin_sees_all_products_including_hidden"

# Cleanup
:
