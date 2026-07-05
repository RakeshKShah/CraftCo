#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-browse-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-browse-${CASE_SUFFIX}"
PROD1_ID="prod-001-${CASE_SUFFIX}"
PROD2_ID="prod-002-${CASE_SUFFIX}"
PROD3_ID="prod-003-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/browse_all_products_as_buyer_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/browse_all_products_as_buyer_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id IN ('${PROD1_ID}', '${PROD2_ID}', '${PROD3_ID}');
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', 'browse-seller-${CASE_SUFFIX}@example.com', 'seeded-hash', 'SELLER', 'ACTIVE', NOW());
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Browse Store ${CASE_SUFFIX}', 'Seed data');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD1_ID}', '${SELLER_PROFILE_ID}', 'Vintage Camera', 'Film camera in working condition', 'Collectibles', 12000, 5, '[]'::jsonb, 'ACTIVE', true, '2024-01-01T10:00:00Z'),
  ('${PROD2_ID}', '${SELLER_PROFILE_ID}', 'Antique Clock', 'Sold out antique clock', 'Collectibles', 18000, 0, '[]'::jsonb, 'ACTIVE', true, '2024-01-02T10:00:00Z'),
  ('${PROD3_ID}', '${SELLER_PROFILE_ID}', 'Modern Lamp', 'Desk lamp with LED bulb', 'Home', 6500, 3, '[]'::jsonb, 'ACTIVE', true, '2024-01-03T10:00:00Z');
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "200" ]
jq -e 'length == 3' "$RESPONSE_FILE" >/dev/null
jq -e '.[0].id == "'"${PROD3_ID}"'" and .[1].id == "'"${PROD2_ID}"'" and .[2].id == "'"${PROD1_ID}"'"' "$RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"${PROD2_ID}"'" and .stockQty == 0)) | length == 1' "$RESPONSE_FILE" >/dev/null
jq -e 'all(.[]; has("seller") and .seller != null)' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:browse_all_products_as_buyer"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM products WHERE id IN ('${PROD1_ID}', '${PROD2_ID}', '${PROD3_ID}');
DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}';
DELETE FROM users WHERE id = '${SELLER_USER_ID}';
SQL
