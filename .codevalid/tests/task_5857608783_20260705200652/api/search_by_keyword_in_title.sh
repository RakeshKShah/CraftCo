#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-keyword-title-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-keyword-title-${CASE_SUFFIX}"
PROD1_ID="prod-201-${CASE_SUFFIX}"
PROD2_ID="prod-202-${CASE_SUFFIX}"
PROD3_ID="prod-203-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/search_by_keyword_in_title_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/search_by_keyword_in_title_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id IN ('${PROD1_ID}', '${PROD2_ID}', '${PROD3_ID}');
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', 'keyword-title-seller-${CASE_SUFFIX}@example.com', 'seeded-hash', 'SELLER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Audio Store ${CASE_SUFFIX}', 'Seed data');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD1_ID}', '${SELLER_PROFILE_ID}', 'Wireless Bluetooth Headphones', 'High quality audio', 'Audio', 12999, 5, '[]'::jsonb, 'ACTIVE', true, NOW()),
  ('${PROD2_ID}', '${SELLER_PROFILE_ID}', 'Wired Earbuds', 'Affordable audio solution', 'Audio', 2999, 5, '[]'::jsonb, 'ACTIVE', true, NOW() + interval '1 second'),
  ('${PROD3_ID}', '${SELLER_PROFILE_ID}', 'Bluetooth Speaker', 'Portable speaker system', 'Audio', 7999, 5, '[]'::jsonb, 'ACTIVE', true, NOW() + interval '2 second');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products?keyword=bluetooth" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e 'length == 2' "$RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"${PROD1_ID}"'")) | length == 1' "$RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"${PROD3_ID}"'")) | length == 1' "$RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"${PROD2_ID}"'")) | length == 0' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:search_by_keyword_in_title"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id IN ('${PROD1_ID}', '${PROD2_ID}', '${PROD3_ID}');
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
SQL
