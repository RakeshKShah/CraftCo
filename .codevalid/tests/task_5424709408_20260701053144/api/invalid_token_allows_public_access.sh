#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="invalid-token-public-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="invalid-token-public-profile-${CASE_SUFFIX}"
PROD1_ID="prod-001-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/invalid_token_allows_public_access_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/invalid_token_allows_public_access_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
cleanup_db() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id = '${PROD1_ID}'; DELETE FROM seller_profiles WHERE id = '${SELLER_PROFILE_ID}'; DELETE FROM users WHERE id = '${SELLER_USER_ID}';" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES ('${SELLER_USER_ID}', 'invalid-token-${CASE_SUFFIX}@example.com', 'x', 'SELLER', 'ACTIVE', TIMESTAMP '2024-10-01 00:00:00');
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_PROFILE_ID}', '${SELLER_USER_ID}', 'Invalid Token Shop ${CASE_SUFFIX}', 'bio');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES ('${PROD1_ID}', '${SELLER_PROFILE_ID}', 'Public Product ${CASE_SUFFIX}', 'public listing', 'ELECTRONICS', 10100, 9, '[]', 'ACTIVE', true, TIMESTAMP '2024-10-10 00:00:00');
" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products" \
  -H 'Authorization: Bearer invalid-token-xyz' > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
jq -e 'type == "array"' "$RESPONSE_FILE" >/dev/null
jq -e 'map(select(.id == "'"$PROD1_ID"'")) | length == 1' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:invalid_token_allows_public_access"

# Cleanup
:
