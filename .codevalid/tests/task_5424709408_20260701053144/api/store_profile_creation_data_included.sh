#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_ID="store_profile_creation_data_included"
TMP_DIR="$(mktemp -d)"
RESPONSE_FILE="$TMP_DIR/response.json"
LOGIN_FILE="$TMP_DIR/login.json"
ADMIN_EMAIL="${TEST_ID}.admin.${CASE_SUFFIX}@example.com"
ADMIN_PASSWORD='AdminPass123!'

cleanup_db() {
  psql "$DATABASE_URL" <<SQL >/dev/null 2>&1 || true
DELETE FROM seller_profiles WHERE id IN ('seller-profile-001-${CASE_SUFFIX}','seller-profile-002-${CASE_SUFFIX}','seller-profile-003-${CASE_SUFFIX}');
DELETE FROM users WHERE id IN ('admin-008-${CASE_SUFFIX}','user-profile-001-${CASE_SUFFIX}','user-profile-002-${CASE_SUFFIX}','user-profile-003-${CASE_SUFFIX}');
SQL
  rm -rf "$TMP_DIR"
}
trap cleanup_db EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES
  ('admin-008-${CASE_SUFFIX}', '${ADMIN_EMAIL}', '\$2b\$10\$D0hUPmZl7Q3kN6lJzi10Suq5mN0eZZF9RnBbTK1ZBOqVaki3P6KyK', 'ADMIN', 'ACTIVE', '2024-07-01T00:00:00Z'),
  ('user-profile-001-${CASE_SUFFIX}', 'artisan.${CASE_SUFFIX}@store.com', 'seed', 'SELLER', 'PENDING', '2024-07-02T00:00:00Z'),
  ('user-profile-002-${CASE_SUFFIX}', 'tech.${CASE_SUFFIX}@store.com', 'seed', 'SELLER', 'ACTIVE', '2024-07-03T00:00:00Z'),
  ('user-profile-003-${CASE_SUFFIX}', 'vintage.${CASE_SUFFIX}@store.com', 'seed', 'SELLER', 'SUSPENDED', '2024-07-04T00:00:00Z');
INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES
  ('seller-profile-001-${CASE_SUFFIX}', 'user-profile-001-${CASE_SUFFIX}', 'Artisan Crafts', 'Handmade goods from local artisans'),
  ('seller-profile-002-${CASE_SUFFIX}', 'user-profile-002-${CASE_SUFFIX}', 'Tech Gadgets', 'Latest electronics and accessories'),
  ('seller-profile-003-${CASE_SUFFIX}', 'user-profile-003-${CASE_SUFFIX}', 'Vintage Finds', 'Antique and vintage items');
SQL
curl -sS -o "$LOGIN_FILE" -X POST "$BASE_URL/auth/login" \n  -H 'Content-Type: application/json' \n  --data "{"email":"$ADMIN_EMAIL","password":"AdminPass123!"}"
ADMIN_TOKEN="$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$LOGIN_FILE")"
[ -n "$ADMIN_TOKEN" ]

# When
HTTP_CODE="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/admin/sellers" -H "Authorization: Bearer $ADMIN_TOKEN")"

# Then
[ "$HTTP_CODE" = "200" ]
COUNT="$(grep -o '"id":"seller-profile-[^"]*' "$RESPONSE_FILE" | wc -l | tr -d ' ')"
[ "$COUNT" = "3" ]
grep -F '"store_name":"Artisan Crafts"' "$RESPONSE_FILE" >/dev/null
grep -F '"bio":"Handmade goods from local artisans"' "$RESPONSE_FILE" >/dev/null
grep -F '"store_name":"Tech Gadgets"' "$RESPONSE_FILE" >/dev/null
grep -F '"bio":"Latest electronics and accessories"' "$RESPONSE_FILE" >/dev/null
grep -F '"store_name":"Vintage Finds"' "$RESPONSE_FILE" >/dev/null
grep -F '"bio":"Antique and vintage items"' "$RESPONSE_FILE" >/dev/null
echo 'CODEVALID_TEST_ASSERTION_OK:store_profile_creation_data_included'

# Cleanup
cleanup_db
trap - EXIT
