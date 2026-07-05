#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
OWNER_USER_ID="user-auth-owner-${CASE_SUFFIX}"
OWNER_SELLER_ID="seller-auth-owner-${CASE_SUFFIX}"
PRODUCT_ID="prod-auth-8-${CASE_SUFFIX}"
OWNER_EMAIL="auth-owner-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/delete_product_with_missing_auth_middleware_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/delete_product_with_missing_auth_middleware_${CASE_SUFFIX}.status"

cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}

cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '${PRODUCT_ID}'; DELETE FROM seller_profiles WHERE id = '${OWNER_SELLER_ID}'; DELETE FROM users WHERE id = '${OWNER_USER_ID}';" >/dev/null
}

trap 'cleanup_files; cleanup_db' EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status) VALUES ('${OWNER_USER_ID}', '${OWNER_EMAIL}', 'hash', 'SELLER', 'ACTIVE');
INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('${OWNER_SELLER_ID}', '${OWNER_USER_ID}', 'Auth Store ${CASE_SUFFIX}', 'bio');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible)
VALUES ('${PRODUCT_ID}', '${OWNER_SELLER_ID}', 'Auth Product ${CASE_SUFFIX}', 'desc', 'crafts', 1750, 4, '[]'::jsonb, 'ACTIVE', true);
SQL

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X DELETE \
  "$BASE_URL/products/${PRODUCT_ID}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "401" ]
grep -F '"error":"Unauthorized"' "$RESPONSE_FILE" >/dev/null
DB_ROW="$(psql "$DATABASE_URL" -At -c "SELECT status || '|' || visible::text FROM products WHERE id = '${PRODUCT_ID}';")"
[ "$DB_ROW" = "ACTIVE|true" ]
echo "CODEVALID_TEST_ASSERTION_OK:delete_product_with_missing_auth_middleware"

# Cleanup
cleanup_db
