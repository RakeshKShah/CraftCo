#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-instock-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-instock-${CASE_SUFFIX}"
PROD1_ID="prod-501-${CASE_SUFFIX}"
PROD2_ID="prod-502-${CASE_SUFFIX}"
PROD3_ID="prod-503-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/filter_in_stock_only_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/filter_in_stock_only_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id IN ('${PROD1_ID}', '${PROD2_ID}', '${PROD3_ID}');
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', 'instock-seller-${CASE_SUFFIX}@example.com', 'seeded-hash', 'SELLER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Inventory Store ${CASE_SUFFIX}', 'Seed data');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD1_ID}', '${SELLER_PROFILE_ID}', 'In Stock Item A', 'Available now', 'General', 1000, 10, '[]'::jsonb, 'ACTIVE', true, NOW()),
  ('${PROD2_ID}', '${SELLER_PROFILE_ID}', 'In Stock Item B', 'Available now', 'General', 1200, 3, '[]'::jsonb, 'ACTIVE', true, NOW() + interval '1 second'),
  ('${PROD3_ID}', '${SELLER_PROFILE_ID}', 'Out of Stock Item', 'Currently unavailable', 'General', 900, 0, '[]'::jsonb, 'ACTIVE', true, NOW() + interval '2 second');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products?in_stock=true" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e 'length == 2' "$RESPONSE_FILE" >/dev/null
jq -e 'all(.[]; .stockQty > 0)' "$RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"${PROD3_ID}"'")) | length == 0' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:filter_in_stock_only"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id IN ('${PROD1_ID}', '${PROD2_ID}', '${PROD3_ID}');
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
SQL
