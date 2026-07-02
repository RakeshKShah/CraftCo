#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="/tmp/missing_auth_token_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/missing_auth_token_${CASE_SUFFIX}.status"
cleanup() {
  rm -f "$RESPONSE_FILE" "$STATUS_FILE"
}
trap cleanup EXIT

# Given
TITLE="Missing Auth ${CASE_SUFFIX}"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  --data "{\"title\":\"${TITLE}\",\"description\":\"Unauthorized\",\"category\":\"ART\",\"price_cents\":1000,\"stock_qty\":2,\"photos\":[]}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "401" ]
grep -F '"error":"Unauthorized"' "$RESPONSE_FILE" >/dev/null
echo "CODEVALID_TEST_ASSERTION_OK:missing_auth_token"
