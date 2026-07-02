#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SUSP_USER_ID="suspended-hidden-user-${CASE_SUFFIX}"
SUSP_PROFILE_ID="suspended-hidden-profile-${CASE_SUFFIX}"
ACTIVE_USER_ID="active-visible-user-${CASE_SUFFIX}"
ACTIVE_PROFILE_ID="active-visible-profile-${CASE_SUFFIX}"
PROD1_ID="prod-001-${CASE_SUFFIX}"
PROD2_ID="prod-002-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/suspended_seller_listings_hidden_from_buyer_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/suspended_seller_listings_hidden_from_buyer_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
cleanup_db() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id IN ('${PROD1_ID}','${PROD2_ID}'); DELETE FROM seller_profiles WHERE id IN ('${SUSP_PROFILE_ID}','${ACTIVE_PROFILE_ID}'); DELETE FROM users WHERE id IN ('${SUSP_USER_ID}','${ACTIVE_USER_ID}');" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES
  ('${SUSP_USER_ID}', 'suspended-shop-${CASE_SUFFIX}@example.com', 'x', 'SELLER', 'SUSPENDED', TIMESTAMP '2024-03-01 00:00:00'),
  ('${ACTIVE_USER_ID}', 'active-shop-${CASE_SUFFIX}@example.com', 'x', 'SELLER', 'ACTIVE', TIMESTAMP '2024-03-01 00:00:01');
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES
  ('${SUSP_PROFILE_ID}', '${SUSP_USER_ID}', 'Suspended Shop ${CASE_SUFFIX}', 'Test seller'),
  ('${ACTIVE_PROFILE_ID}', '${ACTIVE_USER_ID}', 'Active Shop ${CASE_SUFFIX}', 'Active seller');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD1_ID}', '${SUSP_PROFILE_ID}', 'Suspended Product ${CASE_SUFFIX}', 'should be hidden', 'ELECTRONICS', 3100, 4, '[]', 'ACTIVE', false, TIMESTAMP '2024-03-10 00:00:00'),
  ('${PROD2_ID}', '${ACTIVE_PROFILE_ID}', 'Active Product ${CASE_SUFFIX}', 'should be visible', 'ELECTRONICS', 3200, 4, '[]', 'ACTIVE', true, TIMESTAMP '2024-03-09 00:00:00');
" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
jq -e 'type == "array"' "$RESPONSE_FILE" >/dev/null
jq -e 'length == 1' "$RESPONSE_FILE" >/dev/null
jq -e '.[0].id == "'"$PROD2_ID"'"' "$RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"$PROD1_ID"'")) | length == 0' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:suspended_seller_listings_hidden_from_buyer"

# Cleanup
:
