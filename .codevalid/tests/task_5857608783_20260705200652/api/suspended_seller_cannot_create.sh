#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
USER_ID="seller-sus-${CASE_SUFFIX}"
SELLER_ID="sp-sus-${CASE_SUFFIX}"
USER_EMAIL="sellersus-${CASE_SUFFIX}@example.com"
PRODUCT_TITLE="Suspended Item ${CASE_SUFFIX}"
PAYLOAD_FILE="/tmp/suspended_seller_cannot_create_${CASE_SUFFIX}.payload.json"
RESPONSE_FILE="/tmp/suspended_seller_cannot_create_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/suspended_seller_cannot_create_${CASE_SUFFIX}.status"

cleanup_files() {
  rm -f "$PAYLOAD_FILE" "$RESPONSE_FILE" "$STATUS_FILE"
}

create_jwt() {
  payload="$1"
  header_b64="$(printf '%s' '{"alg":"HS256","typ":"JWT"}' | openssl base64 -A | tr '+/' '-_' | tr -d '=')"
  payload_b64="$(printf '%s' "$payload" | openssl base64 -A | tr '+/' '-_' | tr -d '=')"
  signature_b64="$(printf '%s' "${header_b64}.${payload_b64}" | openssl dgst -sha256 -hmac "$JWT_SECRET" -binary | openssl base64 -A | tr '+/' '-_' | tr -d '=')"
  printf '%s' "${header_b64}.${payload_b64}.${signature_b64}"
}

cleanup_db() {
  psql "$DATABASE_URL" -c "DELETE FROM products WHERE title = '${PRODUCT_TITLE}'; DELETE FROM seller_profiles WHERE id = '${SELLER_ID}'; DELETE FROM users WHERE id = '${USER_ID}';" >/dev/null
}

trap 'cleanup_files; cleanup_db' EXIT

# Given
psql "$DATABASE_URL" <<SQL >/dev/null
INSERT INTO users (id, email, password_hash, role, status)
VALUES ('${USER_ID}', '${USER_EMAIL}', 'hash', 'SELLER', 'SUSPENDED');
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_ID}', '${USER_ID}', 'Suspended Store ${CASE_SUFFIX}', 'bio');
SQL
TOKEN="$(create_jwt "{\"id\":\"${USER_ID}\",\"email\":\"${USER_EMAIL}\",\"role\":\"SELLER\",\"status\":\"SUSPENDED\"}")"

# When
cat > "$PAYLOAD_FILE" <<EOF
{
  "title": "${PRODUCT_TITLE}",
  "description": "Suspended seller item",
  "category": "SPORTS",
  "price_cents": 800,
  "stock_qty": 2,
  "photos": []
}
EOF
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST \
  "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  --data @"$PAYLOAD_FILE" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "403" ]
grep -F '"error":"Suspended sellers cannot create products"' "$RESPONSE_FILE" >/dev/null
PRODUCT_COUNT="$(psql "$DATABASE_URL" -At -c "SELECT COUNT(*) FROM products WHERE title = '${PRODUCT_TITLE}';")"
[ "$PRODUCT_COUNT" = "0" ]
echo "CODEVALID_TEST_ASSERTION_OK:suspended_seller_cannot_create"

# Cleanup
cleanup_db
