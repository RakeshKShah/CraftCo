#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-empty-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-empty-${CASE_SUFFIX}"
NOISE_PRODUCT_ID="prod-empty-noise-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/empty_results_no_matching_products_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/empty_results_no_matching_products_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id = '${NOISE_PRODUCT_ID}';
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', 'empty-seller-${CASE_SUFFIX}@example.com', 'seeded-hash', 'SELLER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Empty Store ${CASE_SUFFIX}', 'Seed data');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES ('${NOISE_PRODUCT_ID}', '${SELLER_PROFILE_ID}', 'Noise Product', 'Different category only', 'OtherCategory', 1000, 1, '[]'::jsonb, 'ACTIVE', true, NOW());
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products?category=NonExistentCategory" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e 'length == 0' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:empty_results_no_matching_products"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id = '${NOISE_PRODUCT_ID}';
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
SQL
