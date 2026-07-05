#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TMP_DIR="$(mktemp -d)"
RESPONSE_FILE="$TMP_DIR/response-${CASE_SUFFIX}.json"
STATUS_FILE="$TMP_DIR/status-${CASE_SUFFIX}.txt"
trap 'rm -rf "$TMP_DIR"' EXIT

# Given
INVALID_EMAIL="not-an-email-${CASE_SUFFIX}"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${INVALID_EMAIL}\",\"password\":\"ValidPass123!\",\"role\":\"SELLER\",\"storeName\":\"Test Shop ${CASE_SUFFIX}\"}" > "$STATUS_FILE"

# Then
[ "$(cat "$STATUS_FILE")" = "400" ]
jq -e '.error | ascii_downcase | test("email")' "$RESPONSE_FILE" >/dev/null
echo "CODEVALID_TEST_ASSERTION_OK:invalid_email_format_validation"
