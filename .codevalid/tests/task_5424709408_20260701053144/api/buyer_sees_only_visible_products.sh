#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER1_USER_ID="buyer-visible-seller1-user-${CASE_SUFFIX}"
SELLER1_PROFILE_ID="buyer-visible-seller1-profile-${CASE_SUFFIX}"
SELLER2_USER_ID="buyer-visible-seller2-user-${CASE_SUFFIX}"
SELLER2_PROFILE_ID="buyer-visible-seller2-profile-${CASE_SUFFIX}"
SELLER3_USER_ID="buyer-visible-seller3-user-${CASE_SUFFIX}"
SELLER3_PROFILE_ID="buyer-visible-seller3-profile-${CASE_SUFFIX}"
PROD1_ID="prod-001-${CASE_SUFFIX}"
PROD2_ID="prod-002-${CASE_SUFFIX}"
PROD3_ID="prod-003-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/buyer_sees_only_visible_products_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/buyer_sees_only_visible_products_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
cleanup_db() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id IN ('${PROD1_ID}','${PROD2_ID}','${PROD3_ID}'); DELETE FROM seller_profiles WHERE id IN ('${SELLER1_PROFILE_ID}','${SELLER2_PROFILE_ID}','${SELLER3_PROFILE_ID}'); DELETE FROM users WHERE id IN ('${SELLER1_USER_ID}','${SELLER2_USER_ID}','${SELLER3_USER_ID}');" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES
  ('${SELLER1_USER_ID}', 'visible-${CASE_SUFFIX}@example.com', 'x', 'SELLER', 'ACTIVE', TIMESTAMP '2024-01-01 00:00:00'),
  ('${SELLER2_USER_ID}', 'suspended-${CASE_SUFFIX}@example.com', 'x', 'SELLER', 'SUSPENDED', TIMESTAMP '2024-01-01 00:00:01'),
  ('${SELLER3_USER_ID}', 'removed-${CASE_SUFFIX}@example.com', 'x', 'SELLER', 'ACTIVE', TIMESTAMP '2024-01-01 00:00:02');
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES
  ('${SELLER1_PROFILE_ID}', '${SELLER1_USER_ID}', 'Visible Shop ${CASE_SUFFIX}', 'visible bio'),
  ('${SELLER2_PROFILE_ID}', '${SELLER2_USER_ID}', 'Suspended Shop ${CASE_SUFFIX}', 'suspended bio'),
  ('${SELLER3_PROFILE_ID}', '${SELLER3_USER_ID}', 'Removed Shop ${CASE_SUFFIX}', 'removed bio');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD1_ID}', '${SELLER1_PROFILE_ID}', 'Widget A ${CASE_SUFFIX}', 'buyer visible product', 'ELECTRONICS', 1200, 5, '[]', 'ACTIVE', true, TIMESTAMP '2024-01-10 00:00:00'),
  ('${PROD2_ID}', '${SELLER2_PROFILE_ID}', 'Widget B ${CASE_SUFFIX}', 'hidden product', 'ELECTRONICS', 1300, 5, '[]', 'ACTIVE', false, TIMESTAMP '2024-01-09 00:00:00'),
  ('${PROD3_ID}', '${SELLER3_PROFILE_ID}', 'Widget C ${CASE_SUFFIX}', 'removed product', 'ELECTRONICS', 1400, 5, '[]', 'REMOVED', true, TIMESTAMP '2024-01-08 00:00:00');
" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
jq -e 'type == "array"' "$RESPONSE_FILE" >/dev/null
jq -e 'length == 1' "$RESPONSE_FILE" >/dev/null
jq -e '.[0].id == "'"$PROD1_ID"'"' "$RESPONSE_FILE" >/dev/null
jq -e '.[0].title == "Widget A '"$CASE_SUFFIX"'"' "$RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"$PROD2_ID"'")) | length == 0' "$RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"$PROD3_ID"'")) | length == 0' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:buyer_sees_only_visible_products"

# Cleanup
:
