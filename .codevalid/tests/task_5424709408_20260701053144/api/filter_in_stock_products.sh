#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="stock-seller-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="stock-seller-profile-${CASE_SUFFIX}"
PROD1_ID="prod-001-${CASE_SUFFIX}"
PROD2_ID="prod-002-${CASE_SUFFIX}"
PROD3_ID="prod-003-${CASE_SUFFIX}"
RESPONSE_FILE1="/tmp/filter_in_stock_products_1_${CASE_SUFFIX}.json"
STATUS_FILE1="/tmp/filter_in_stock_products_1_${CASE_SUFFIX}.status"
RESPONSE_FILE2="/tmp/filter_in_stock_products_2_${CASE_SUFFIX}.json"
STATUS_FILE2="/tmp/filter_in_stock_products_2_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE1" "$STATUS_FILE1" "$RESPONSE_FILE2" "$STATUS_FILE2"; }
cleanup_db() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id IN ('${PROD1_ID}','${PROD2_ID}','${PROD3_ID}'); DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}'; DELETE FROM users WHERE id = '${SELLER_USER_ID}';" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', 'stock-${CASE_SUFFIX}@example.com', 'x', 'SELLER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Stock Seller ${CASE_SUFFIX}', 'bio');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD1_ID}', '${SELLER_PROFILE_ID}', 'Mouse', 'in stock', 'ELECTRONICS', 1000, 10, '[]', 'ACTIVE', true, NOW()),
  ('${PROD2_ID}', '${SELLER_PROFILE_ID}', 'Keyboard', 'out of stock', 'ELECTRONICS', 1200, 0, '[]', 'ACTIVE', true, NOW() - INTERVAL '1 hour'),
  ('${PROD3_ID}', '${SELLER_PROFILE_ID}', 'Monitor', 'in stock', 'ELECTRONICS', 1500, 5, '[]', 'ACTIVE', true, NOW() - INTERVAL '2 hour');
" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE1" -w '%{http_code}' "$BASE_URL/products?in_stock=true" > "$STATUS_FILE1"
curl -sS -o "$RESPONSE_FILE2" -w '%{http_code}' "$BASE_URL/products?in_stock=false" > "$STATUS_FILE2"

# Then
[ "$(cat "$STATUS_FILE1")" = "200" ]
[ "$(cat "$STATUS_FILE2")" = "200" ]
jq -e 'map(.id) | sort == ["'"$PROD1_ID"'","'"$PROD3_ID"'"] | sort' "$RESPONSE_FILE1" >/dev/null
jq -e 'map(select(.id == "'"$PROD2_ID"'")) | length == 0' "$RESPONSE_FILE1" >/dev/null
jq -e 'map(.id) | sort == ["'"$PROD1_ID"'","'"$PROD2_ID"'","'"$PROD3_ID"'"] | sort' "$RESPONSE_FILE2" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:filter_in_stock_products"

# Cleanup
:
