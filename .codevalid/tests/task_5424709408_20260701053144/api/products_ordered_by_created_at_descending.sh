#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-order-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-order-${CASE_SUFFIX}"
PROD_OLD="prod-old-${CASE_SUFFIX}"
PROD_NEWER="prod-newer-${CASE_SUFFIX}"
PROD_NEWEST="prod-newest-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/products_ordered_by_created_at_descending_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/products_ordered_by_created_at_descending_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
cleanup_db() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id IN ('${PROD_OLD}','${PROD_NEWER}','${PROD_NEWEST}'); DELETE FROM seller_profiles WHERE id='${SELLER_PROFILE_ID}'; DELETE FROM users WHERE id='${SELLER_USER_ID}';" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', 'seller-order-${CASE_SUFFIX}@example.com', '\$2b\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'SELLER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Order Shop ${CASE_SUFFIX}', 'order seller');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD_OLD}', '${SELLER_PROFILE_ID}', 'Old Product ${CASE_SUFFIX}', 'old item', 'electronics', 1000, 5, '[]', 'ACTIVE', true, '2024-01-01T00:00:00Z'),
  ('${PROD_NEWER}', '${SELLER_PROFILE_ID}', 'Newer Product ${CASE_SUFFIX}', 'newer item', 'electronics', 1000, 5, '[]', 'ACTIVE', true, '2024-06-15T00:00:00Z'),
  ('${PROD_NEWEST}', '${SELLER_PROFILE_ID}', 'Newest Product ${CASE_SUFFIX}', 'newest item', 'electronics', 1000, 5, '[]', 'ACTIVE', true, '2024-12-01T00:00:00Z');
" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
FIRST_ID="$(jq -r '.[0].id' "$RESPONSE_FILE")"
SECOND_ID="$(jq -r '.[1].id' "$RESPONSE_FILE")"
THIRD_ID="$(jq -r '.[2].id' "$RESPONSE_FILE")"
[ "$FIRST_ID" = "$PROD_NEWEST" ]
[ "$SECOND_ID" = "$PROD_NEWER" ]
[ "$THIRD_ID" = "$PROD_OLD" ]

echo "CODEVALID_TEST_ASSERTION_OK:products_ordered_by_created_at_descending"

# Cleanup
:
