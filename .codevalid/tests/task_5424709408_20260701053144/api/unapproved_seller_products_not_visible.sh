#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
PENDING_USER_ID="seller-pending-user-${CASE_SUFFIX}"
PENDING_PROFILE_ID="seller-pending-${CASE_SUFFIX}"
APPROVED_USER_ID="seller-approved-user-${CASE_SUFFIX}"
APPROVED_PROFILE_ID="seller-approved-${CASE_SUFFIX}"
PROD_PENDING_ID="prod-pending-${CASE_SUFFIX}"
PROD_APPROVED_ID="prod-approved-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/unapproved_seller_products_not_visible_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/unapproved_seller_products_not_visible_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
cleanup_db() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id IN ('${PROD_PENDING_ID}','${PROD_APPROVED_ID}'); DELETE FROM seller_profiles WHERE id IN ('${PENDING_PROFILE_ID}','${APPROVED_PROFILE_ID}'); DELETE FROM users WHERE id IN ('${PENDING_USER_ID}','${APPROVED_USER_ID}');" >/dev/null 2>&1 || true
}
trap 'cleanup_files; cleanup_db' EXIT

# Given
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "
INSERT INTO users (id, email, password_hash, role, status, created_at)
VALUES
  ('${PENDING_USER_ID}', 'seller-pending-${CASE_SUFFIX}@example.com', '\$2b\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'SELLER', 'PENDING', NOW() - INTERVAL '2 days'),
  ('${APPROVED_USER_ID}', 'seller-approved-${CASE_SUFFIX}@example.com', '\$2b\$10\$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'SELLER', 'ACTIVE', NOW() - INTERVAL '1 day');
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES
  ('${PENDING_PROFILE_ID}', '${PENDING_USER_ID}', 'Pending Shop ${CASE_SUFFIX}', 'pending bio'),
  ('${APPROVED_PROFILE_ID}', '${APPROVED_USER_ID}', 'Approved Shop ${CASE_SUFFIX}', 'approved bio');
INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible, created_at)
VALUES
  ('${PROD_PENDING_ID}', '${PENDING_PROFILE_ID}', 'Pending Product ${CASE_SUFFIX}', 'should not be visible', 'electronics', 9999, 5, '[]', 'ACTIVE', false, NOW()),
  ('${PROD_APPROVED_ID}', '${APPROVED_PROFILE_ID}', 'Approved Product ${CASE_SUFFIX}', 'should be visible', 'electronics', 19999, 5, '[]', 'ACTIVE', true, NOW() - INTERVAL '1 hour');
" >/dev/null

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/products" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "200" ]
! grep -F '"id":"'"$PROD_PENDING_ID"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"id":"'"$PROD_APPROVED_ID"'"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:unapproved_seller_products_not_visible"

# Cleanup
:
