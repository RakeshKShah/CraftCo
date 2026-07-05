#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-case-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-case-${CASE_SUFFIX}"
PROD1_ID="prod-1001-${CASE_SUFFIX}"
PROD2_ID="prod-1002-${CASE_SUFFIX}"
RESPONSE1_FILE="/tmp/keyword_search_case_insensitive_1_${CASE_SUFFIX}.json"
STATUS1_FILE="/tmp/keyword_search_case_insensitive_1_${CASE_SUFFIX}.status"
RESPONSE2_FILE="/tmp/keyword_search_case_insensitive_2_${CASE_SUFFIX}.json"
STATUS2_FILE="/tmp/keyword_search_case_insensitive_2_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE1_FILE" "$STATUS1_FILE" "$RESPONSE2_FILE" "$STATUS2_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id IN ('${PROD1_ID}', '${PROD2_ID}');
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', 'case-seller-${CASE_SUFFIX}@example.com', 'seeded-hash', 'SELLER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Case Store ${CASE_SUFFIX}', 'Seed data');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD1_ID}', '${SELLER_PROFILE_ID}', 'PREMIUM Headphones', 'High-end audio', 'Audio', 15000, 3, '[]'::jsonb, 'ACTIVE', true, NOW()),
  ('${PROD2_ID}', '${SELLER_PROFILE_ID}', 'Basic headphones', 'Budget option', 'Audio', 5000, 7, '[]'::jsonb, 'ACTIVE', true, NOW() + interval '1 second');
SQL

# When
curl -sS -o "$RESPONSE1_FILE" -w '%{http_code}' "$BASE_URL/products?keyword=PREMIUM" > "$STATUS1_FILE"
curl -sS -o "$RESPONSE2_FILE" -w '%{http_code}' "$BASE_URL/products?keyword=headphones" > "$STATUS2_FILE"

# Then
STATUS1="$(cat "$STATUS1_FILE")"
STATUS2="$(cat "$STATUS2_FILE")"
[ "$STATUS1" = "200" ]
[ "$STATUS2" = "200" ]
jq -e 'length == 1 and .[0].id == "'"${PROD1_ID}"'"' "$RESPONSE1_FILE" >/dev/null
jq -e 'length == 2' "$RESPONSE2_FILE" >/dev/null
jq -e 'map(select(.id == "'"${PROD1_ID}"'")) | length == 1' "$RESPONSE2_FILE" >/dev/null
jq -e 'map(select(.id == "'"${PROD2_ID}"'")) | length == 1' "$RESPONSE2_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:keyword_search_case_insensitive"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id IN ('${PROD1_ID}', '${PROD2_ID}');
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
SQL
