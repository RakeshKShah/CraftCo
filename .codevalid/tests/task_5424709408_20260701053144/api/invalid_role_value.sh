#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
INVALID_EMAIL="invalid-role-${CASE_SUFFIX}@test.com"
RESPONSE_FILE="/tmp/invalid_role_value_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/invalid_role_value_${CASE_SUFFIX}.status"
cleanup_files() { rm -f "$RESPONSE_FILE" "$STATUS_FILE"; }
trap cleanup_files EXIT

# Given
: "Registration endpoint available at /auth/register"

# When
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${INVALID_EMAIL}\",\"password\":\"SecurePass123!\",\"role\":\"ADMIN\"}" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "400" ]
grep -F '"error":' "$RESPONSE_FILE" >/dev/null
grep -E 'role|Invalid enum|Invalid input' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:invalid_role_value"
