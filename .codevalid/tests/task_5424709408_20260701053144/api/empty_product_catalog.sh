#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="empty-catalog-seller-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="empty-catalog-seller-profile-${CASE_SUFFIX}"
HIDDEN_PROD_ID="empty-hidden-prod-${CASE_SUFFIX}"
REMOVED_PROD_ID="empty-removed-prod-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/empty_product_catalog_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/empty_product_catalog_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
cleanup_db() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id IN ('${HIDDEN_PROD_ID}','${REMOVED_PROD_ID}'); DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}'; DELETE FROM users WHERE id = '${SELLER_USER_ID}';" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', 'empty-catalog-${CASE_SUFFIX}@example.com', 'x', 'SELLER', 'SUSPENDED', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Empty Catalog Seller', 'bio');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${HIDDEN_PROD_ID}', '${SELLER_PROFILE_ID}', 'Hidden Only', 'not buyer visible', 'ELECTRONICS', 1000, 5, '[]', 'ACTIVE', false, NOW()),
  ('${REMOVED_PROD_ID}', '${SELLER_PROFILE_ID}', 'Removed Only', 'removed', 'ELECTRONICS', 1200, 5, '[]', 'REMOVED', true, NOW() - INTERVAL '1 hour');
" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
jq -e 'type == "array" and length == 0' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:empty_product_catalog"

# Cleanup
:
