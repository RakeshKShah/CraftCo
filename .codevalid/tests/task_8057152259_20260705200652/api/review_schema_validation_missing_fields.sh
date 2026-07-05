#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-/tmp/test_gen_ydh4e25v}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_ID="buyer-review-missing-fields-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/review_schema_validation_missing_fields_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/review_schema_validation_missing_fields_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

make_buyer_token() {
  TEST_USER_ID="$1" node <<'NODE'
const jwt = require('jsonwebtoken');
const secret = process.env.JWT_SECRET || 'dev-secret';
process.stdout.write(jwt.sign({ id: process.env.TEST_USER_ID, role: 'BUYER' }, secret));
NODE
}

# Given
psql "$DATABASE_URL" <<SQL
INSERT INTO users (id, email, password, role, name, created_at)
VALUES ('${BUYER_ID}', 'buyer-review-missing-fields-${CASE_SUFFIX}@example.com', 'pw-hash', 'BUYER', 'Buyer Review Missing Fields ${CASE_SUFFIX}', NOW());
SQL

AUTH_TOKEN="$(cd "$WORKSPACE_ROOT/backend" && make_buyer_token "$BUYER_ID")"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/api/reviews" \
  -H "Authorization: Bearer ${AUTH_TOKEN}" \
  -H 'Content-Type: application/json' \
  --data '{"body":"Missing rating and order_item_id"}' \
  > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "400" ]
jq -e '.error and (.error | type == "string") and (.error | length > 0)' "$RESPONSE_FILE" >/dev/null
grep -E 'Required|Invalid|rating|order_item_id' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:review_schema_validation_missing_fields"

# Cleanup
psql "$DATABASE_URL" <<SQL
DELETE FROM users WHERE id = '${BUYER_ID}';
SQL
