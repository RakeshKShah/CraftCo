#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
BAD_USER_ID="seller-suspended-user-${CASE_SUFFIX}"
BAD_PROFILE_ID="seller-suspended-${CASE_SUFFIX}"
GOOD_USER_ID="seller-active-user-${CASE_SUFFIX}"
GOOD_PROFILE_ID="seller-active-${CASE_SUFFIX}"
BAD_PROD1_ID="prod-bad-1-${CASE_SUFFIX}"
BAD_PROD2_ID="prod-bad-2-${CASE_SUFFIX}"
GOOD_PROD_ID="prod-good-1-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/suspended_seller_products_hidden_from_buyers_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/suspended_seller_products_hidden_from_buyers_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
cleanup_db() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id IN ('${BAD_PROD1_ID}','${BAD_PROD2_ID}','${GOOD_PROD_ID}'); DELETE FROM seller_profiles WHERE id IN ('${BAD_PROFILE_ID}','${GOOD_PROFILE_ID}'); DELETE FROM users WHERE id IN ('${BAD_USER_ID}','${GOOD_USER_ID}');" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES
  ('${BAD_USER_ID}', 'bad-seller-${CASE_SUFFIX}@example.com', 'x', 'SELLER', 'SUSPENDED', NOW() - INTERVAL '2 day'),
  ('${GOOD_USER_ID}', 'good-seller-${CASE_SUFFIX}@example.com', 'x', 'SELLER', 'ACTIVE', NOW() - INTERVAL '1 day');
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES
  ('${BAD_PROFILE_ID}', '${BAD_USER_ID}', 'Bad Seller', 'suspended bio'),
  ('${GOOD_PROFILE_ID}', '${GOOD_USER_ID}', 'Good Seller', 'active bio');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${BAD_PROD1_ID}', '${BAD_PROFILE_ID}', 'Suspended Product 1', 'hidden from buyers', 'ELECTRONICS', 1000, 5, '[]', 'ACTIVE', false, NOW()),
  ('${BAD_PROD2_ID}', '${BAD_PROFILE_ID}', 'Suspended Product 2', 'hidden from buyers', 'ELECTRONICS', 1200, 5, '[]', 'ACTIVE', false, NOW() - INTERVAL '1 hour'),
  ('${GOOD_PROD_ID}', '${GOOD_PROFILE_ID}', 'Active Product', 'visible item', 'ELECTRONICS', 1500, 5, '[]', 'ACTIVE', true, NOW() - INTERVAL '2 hour');
" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
jq -e 'type == "array"' "$RESPONSE_FILE" >/dev/null
jq -e 'length == 1' "$RESPONSE_FILE" >/dev/null
jq -e '.[0].id == "'"$GOOD_PROD_ID"'"' "$RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"$BAD_PROD1_ID"'")) | length == 0' "$RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"$BAD_PROD2_ID"'")) | length == 0' "$RESPONSE_FILE" >/dev/null
! grep -F 'Bad Seller' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:suspended_seller_products_hidden_from_buyers"

# Cleanup
:
