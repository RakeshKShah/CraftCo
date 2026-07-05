#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-keyword-description-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-keyword-description-${CASE_SUFFIX}"
PROD1_ID="prod-301-${CASE_SUFFIX}"
PROD2_ID="prod-302-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/search_by_keyword_in_description_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/search_by_keyword_in_description_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id IN ('${PROD1_ID}', '${PROD2_ID}');
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', 'keyword-description-seller-${CASE_SUFFIX}@example.com', 'seeded-hash', 'SELLER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Lighting Store ${CASE_SUFFIX}', 'Seed data');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD1_ID}', '${SELLER_PROFILE_ID}', 'Desk Lamp', 'Modern LED lighting for office use', 'Home', 5400, 7, '[]'::jsonb, 'ACTIVE', true, NOW()),
  ('${PROD2_ID}', '${SELLER_PROFILE_ID}', 'Floor Lamp', 'Traditional bulb design', 'Home', 7400, 4, '[]'::jsonb, 'ACTIVE', true, NOW() + interval '1 second');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products?keyword=LED" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e 'length == 1' "$RESPONSE_FILE" >/dev/null
jq -e '.[0].id == "'"${PROD1_ID}"'"' "$RESPONSE_FILE" >/dev/null
jq -e '.[0].description | ascii_downcase | contains("led")' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:search_by_keyword_in_description"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id IN ('${PROD1_ID}', '${PROD2_ID}');
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
SQL
