#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="combined-seller-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="combined-seller-profile-${CASE_SUFFIX}"
PROD1_ID="prod-001-${CASE_SUFFIX}"
PROD2_ID="prod-002-${CASE_SUFFIX}"
PROD3_ID="prod-003-${CASE_SUFFIX}"
PROD4_ID="prod-004-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/combined_filters_on_product_search_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/combined_filters_on_product_search_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
cleanup_db() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id IN ('${PROD1_ID}','${PROD2_ID}','${PROD3_ID}','${PROD4_ID}'); DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}'; DELETE FROM users WHERE id = '${SELLER_USER_ID}';" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', 'combined-${CASE_SUFFIX}@example.com', 'x', 'SELLER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Combined Seller ${CASE_SUFFIX}', 'bio');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD1_ID}', '${SELLER_PROFILE_ID}', 'Wireless Mouse', 'great wireless mouse', 'ELECTRONICS', 1000, 10, '[]', 'ACTIVE', true, NOW()),
  ('${PROD2_ID}', '${SELLER_PROFILE_ID}', 'Wireless Keyboard', 'wireless keyboard', 'ELECTRONICS', 1200, 0, '[]', 'ACTIVE', true, NOW() - INTERVAL '1 hour'),
  ('${PROD3_ID}', '${SELLER_PROFILE_ID}', 'Wireless Speaker', 'wireless audio speaker', 'AUDIO', 1500, 5, '[]', 'ACTIVE', true, NOW() - INTERVAL '2 hour'),
  ('${PROD4_ID}', '${SELLER_PROFILE_ID}', 'Wired Mouse', 'corded mouse', 'ELECTRONICS', 1600, 8, '[]', 'ACTIVE', true, NOW() - INTERVAL '3 hour');
" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products?category=ELECTRONICS&keyword=wireless&in_stock=true" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
jq -e 'length == 1' "$RESPONSE_FILE" >/dev/null
jq -e '.[0].id == "'"$PROD1_ID"'"' "$RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"$PROD2_ID"'")) | length == 0' "$RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"$PROD3_ID"'")) | length == 0' "$RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"$PROD4_ID"'")) | length == 0' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:combined_filters_on_product_search"

# Cleanup
:
