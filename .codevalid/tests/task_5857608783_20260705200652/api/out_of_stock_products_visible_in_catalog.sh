#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-soldout-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-soldout-${CASE_SUFFIX}"
PROD_SOLDOUT_ID="prod-soldout-${CASE_SUFFIX}"
PROD_AVAILABLE_ID="prod-available-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/out_of_stock_products_visible_in_catalog_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/out_of_stock_products_visible_in_catalog_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id IN ('${PROD_SOLDOUT_ID}', '${PROD_AVAILABLE_ID}');
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', 'soldout-seller-${CASE_SUFFIX}@example.com', 'seeded-hash', 'SELLER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Vinyl Store ${CASE_SUFFIX}', 'Seed data');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD_SOLDOUT_ID}', '${SELLER_PROFILE_ID}', 'Rare Vinyl Record', 'Hard to find album', 'Music', 4500, 0, '[]'::jsonb, 'ACTIVE', true, NOW()),
  ('${PROD_AVAILABLE_ID}', '${SELLER_PROFILE_ID}', 'Common Vinyl Record', 'Popular album', 'Music', 2500, 10, '[]'::jsonb, 'ACTIVE', true, NOW() + interval '1 second');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e 'map(select(.id == "'"${PROD_SOLDOUT_ID}"'" and .stockQty == 0)) | length == 1' "$RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"${PROD_AVAILABLE_ID}"'" and .stockQty == 10)) | length == 1' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:out_of_stock_products_visible_in_catalog"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id IN ('${PROD_SOLDOUT_ID}', '${PROD_AVAILABLE_ID}');
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
SQL
