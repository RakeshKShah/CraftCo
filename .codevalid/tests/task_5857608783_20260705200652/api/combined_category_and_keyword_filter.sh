#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-combined-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-combined-${CASE_SUFFIX}"
PROD1_ID="prod-401-${CASE_SUFFIX}"
PROD2_ID="prod-402-${CASE_SUFFIX}"
PROD3_ID="prod-403-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/combined_category_and_keyword_filter_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/combined_category_and_keyword_filter_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id IN ('${PROD1_ID}', '${PROD2_ID}', '${PROD3_ID}');
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', 'combined-seller-${CASE_SUFFIX}@example.com', 'seeded-hash', 'SELLER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Sports Store ${CASE_SUFFIX}', 'Seed data');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD1_ID}', '${SELLER_PROFILE_ID}', 'Running Shoes Pro', 'Professional running gear', 'Footwear', 12000, 9, '[]'::jsonb, 'ACTIVE', true, NOW()),
  ('${PROD2_ID}', '${SELLER_PROFILE_ID}', 'Walking Shoes Basic', 'Casual walking shoes', 'Footwear', 6500, 8, '[]'::jsonb, 'ACTIVE', true, NOW() + interval '1 second'),
  ('${PROD3_ID}', '${SELLER_PROFILE_ID}', 'Running Shirt', 'Athletic wear', 'Apparel', 3500, 10, '[]'::jsonb, 'ACTIVE', true, NOW() + interval '2 second');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products?category=Footwear&keyword=running" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e 'length == 1' "$RESPONSE_FILE" >/dev/null
jq -e '.[0].id == "'"${PROD1_ID}"'" and .[0].category == "Footwear"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:combined_category_and_keyword_filter"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id IN ('${PROD1_ID}', '${PROD2_ID}', '${PROD3_ID}');
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
SQL
