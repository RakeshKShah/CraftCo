#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="non_authenticated_request_rejected"
TMP_DIR="$(mktemp -d)"
RESPONSE_FILE="$TMP_DIR/response.json"

cleanup_db() {
  psql "$DATABASE_URL" <<SQL >/dev/null 2>&1 || true
DELETE FROM seller_profiles WHERE id = 'seller-authless-${CASE_SUFFIX}';
DELETE FROM users WHERE id = 'user-authless-${CASE_SUFFIX}';
SQL
  rm -rf "$TMP_DIR"
}
trap cleanup_db EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES
  ('user-authless-${CASE_SUFFIX}', 'authless.${CASE_SUFFIX}@store.com', 'seed', 'SELLER', 'ACTIVE', '2024-08-01T00:00:00Z');
INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES
  ('seller-authless-${CASE_SUFFIX}', 'user-authless-${CASE_SUFFIX}', 'Authless Seller', 'Visible only to authorized admins');
SQL

# When
HTTP_CODE="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/admin/sellers")"

# Then
[ "$HTTP_CODE" = "401" ]
grep -F '"error":"Unauthorized"' "$RESPONSE_FILE" >/dev/null
echo 'CODEVALID_TEST_ASSERTION_OK:non_authenticated_request_rejected'

# Cleanup
cleanup_db
trap - EXIT
