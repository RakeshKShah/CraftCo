#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="combined-filter-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="combined-filter-profile-${CASE_SUFFIX}"
PROD1_ID="prod-001-${CASE_SUFFIX}"
PROD2_ID="prod-002-${CASE_SUFFIX}"
PROD3_ID="prod-003-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/combined_filters_for_buyer_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/combined_filters_for_buyer_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
cleanup_db() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id IN ('${PROD1_ID}','${PROD2_ID}','${PROD3_ID}'); DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}'; DELETE FROM users WHERE id = '${SELLER_USER_ID}';" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', 'combined-${CASE_SUFFIX}@example.com', 'x', 'SELLER', 'ACTIVE', TIMESTAMP '2024-11-01 00:00:00');
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Combined Shop ${CASE_SUFFIX}', 'bio');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD1_ID}', '${SELLER_PROFILE_ID}', 'Wireless Electronics Mouse ${CASE_SUFFIX}', 'wireless mouse for computers', 'ELECTRONICS', 11100, 5, '[]', 'ACTIVE', true, TIMESTAMP '2024-11-10 00:00:00'),
  ('${PROD2_ID}', '${SELLER_PROFILE_ID}', 'Wireless Electronics Keyboard ${CASE_SUFFIX}', 'wireless keyboard but out of stock', 'ELECTRONICS', 11200, 0, '[]', 'ACTIVE', true, TIMESTAMP '2024-11-09 00:00:00'),
  ('${PROD3_ID}', '${SELLER_PROFILE_ID}', 'Wireless Clothing ${CASE_SUFFIX}', 'wireless themed clothing', 'CLOTHING', 11300, 10, '[]', 'ACTIVE', true, TIMESTAMP '2024-11-08 00:00:00');
" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products?category=ELECTRONICS&keyword=wireless&in_stock=true" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
jq -e 'type == "array"' "$RESPONSE_FILE" >/dev/null
jq -e 'length == 1' "$RESPONSE_FILE" >/dev/null
jq -e '.[0].id == "'"$PROD1_ID"'"' "$RESPONSE_FILE" >/dev/null
jq -e '.[0].category == "ELECTRONICS"' "$RESPONSE_FILE" >/dev/null
jq -e '.[0].stock_qty > 0' "$RESPONSE_FILE" >/dev/null
jq -e '((.[0].title + " " + .[0].description) | ascii_downcase | contains("wireless"))' "$RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"$PROD2_ID"'")) | length == 0' "$RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"$PROD3_ID"'")) | length == 0' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:combined_filters_for_buyer"

# Cleanup
:
