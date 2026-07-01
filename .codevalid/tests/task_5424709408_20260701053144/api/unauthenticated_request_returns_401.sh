#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="/tmp/unauthenticated_request_returns_401_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/unauthenticated_request_returns_401_${CASE_SUFFIX}.status"
cleanup() {
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE title='Unauth Product ${CASE_SUFFIX}';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
trap cleanup EXIT

# Given
: "No Authorization header is provided for this request"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  --data "{\"title\":\"Unauth Product ${CASE_SUFFIX}\",\"description\":\"No auth\",\"category\":\"MISC\",\"price_cents\":100,\"stock_qty\":1,\"photos\":[]}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "401" ]
grep -F '"error":"Unauthorized"' "$RESPONSE_FILE" >/dev/null
DB_COUNT="$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM products WHERE title='Unauth Product ${CASE_SUFFIX}';")"
[ "$DB_COUNT" = "0" ]
echo "CODEVALID_TEST_ASSERTION_OK:unauthenticated_request_returns_401"

# Cleanup
rm -f "$RESPONSE_FILE" "$STATUS_FILE"
