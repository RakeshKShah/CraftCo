#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-data-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-001-${CASE_SUFFIX}"
PROD1_ID="prod-001-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/product_response_includes_seller_data_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/product_response_includes_seller_data_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
cleanup_db() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id = '${PROD1_ID}'; DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}'; DELETE FROM users WHERE id = '${SELLER_USER_ID}';" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', 'seller-data-${CASE_SUFFIX}@example.com', 'x', 'SELLER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Tech Store', 'Quality electronics seller');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES ('${PROD1_ID}', '${SELLER_PROFILE_ID}', 'Mouse', 'good mouse', 'ELECTRONICS', 1000, 5, '[]', 'ACTIVE', true, NOW());
" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
jq -e 'length >= 1' "$RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"$PROD1_ID"'" and .seller != null and .seller.id == "'"$SELLER_PROFILE_ID"'" and .seller.name == "Tech Store" and .seller.bio == "Quality electronics seller")) | length == 1' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:product_response_includes_seller_data"

# Cleanup
:
