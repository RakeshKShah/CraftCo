#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
USER_A_ID="user-seller-A-${CASE_SUFFIX}"
SELLER_A_ID="seller-A-${CASE_SUFFIX}"
USER_B_ID="user-seller-B-${CASE_SUFFIX}"
SELLER_B_ID="seller-B-${CASE_SUFFIX}"
PRODUCT_ID="prod-ownedB-${CASE_SUFFIX}"
USER_A_EMAIL="seller-a-${CASE_SUFFIX}@example.com"
USER_B_EMAIL="seller-b-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/delete_product_not_owned_by_seller_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/delete_product_not_owned_by_seller_${CASE_SUFFIX}.status"

cleanup_files() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}

create_jwt() {
  payload="$1"
  header_b64="$(printf '%s' '{"alg":"HS256","typ":"JWT"}' | openssl base64 -A | tr '+/' '-_' | tr -d '=')"
  payload_b64="$(printf '%s' "$payload" | openssl base64 -A | tr '+/' '-_' | tr -d '=')"
  signature_b64="$(printf '%s' "${header_b64}.${payload_b64}" | openssl dgst -sha256 -hmac "$JWT_SECRET" -binary | openssl base64 -A | tr '+/' '-_' | tr -d '=')"
  printf '%s' "${header_b64}.${payload_b64}.${signature_b64}"
}

cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE id = '${PRODUCT_ID}'; DELETE FROM seller_profiles WHERE id IN ('${SELLER_A_ID}', '${SELLER_B_ID}'); DELETE FROM users WHERE id IN ('${USER_A_ID}', '${USER_B_ID}');" >/dev/null
}

trap 'cleanup_files; cleanup_db' EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status) VALUES ('${USER_A_ID}', '${USER_A_EMAIL}', 'hash', 'SELLER', 'ACTIVE');
INSERT INTO users (id, email, password_hash, role, status) VALUES ('${USER_B_ID}', '${USER_B_EMAIL}', 'hash', 'SELLER', 'ACTIVE');
INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('${SELLER_A_ID}', '${USER_A_ID}', 'Store A ${CASE_SUFFIX}', 'bio');
INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('${SELLER_B_ID}', '${USER_B_ID}', 'Store B ${CASE_SUFFIX}', 'bio');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible)
VALUES ('${PRODUCT_ID}', '${SELLER_B_ID}', 'B Product ${CASE_SUFFIX}', 'desc', 'crafts', 2200, 7, '[]'::jsonb, 'ACTIVE', true);
SQL
TOKEN="$(create_jwt "{\"id\":\"${USER_A_ID}\",\"email\":\"${USER_A_EMAIL}\",\"role\":\"SELLER\",\"status\":\"ACTIVE\"}")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X DELETE \
  "$BASE_URL/products/${PRODUCT_ID}" \
  -H "Authorization: Bearer ${TOKEN}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "404" ]
grep -F '"error":"Product not found"' "$RESPONSE_FILE" >/dev/null
DB_ROW="$(psql "$DATABASE_URL" -At -c "SELECT status || '|' || visible::text FROM products WHERE id = '${PRODUCT_ID}';")"
[ "$DB_ROW" = "ACTIVE|true" ]
echo "CODEVALID_TEST_ASSERTION_OK:delete_product_not_owned_by_seller"

# Cleanup
cleanup_db
