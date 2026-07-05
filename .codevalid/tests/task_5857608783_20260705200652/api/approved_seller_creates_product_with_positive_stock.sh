#!/usr/bin/env sh
set -eu
BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
JWT_SECRET="${JWT_SECRET:-dev-secret}"
CASE_SUFFIX="$(date +%s)-$$"
USER_ID="seller-01-${CASE_SUFFIX}"
SELLER_ID="sp-01-${CASE_SUFFIX}"
USER_EMAIL="seller01-${CASE_SUFFIX}@example.com"
PRODUCT_TITLE="Vintage Lamp ${CASE_SUFFIX}"
PAYLOAD_FILE="/tmp/approved_seller_creates_product_with_positive_stock_${CASE_SUFFIX}.payload.json"
RESPONSE_FILE="/tmp/approved_seller_creates_product_with_positive_stock_${CASE_SUFFIX}.json"
STATUS_FILE="/tmp/approved_seller_creates_product_with_positive_stock_${CASE_SUFFIX}.status"

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
VALUES ('${USER_ID}', '${USER_EMAIL}', 'hash', 'SELLER', 'APPROVED');
INSERT INTO seller_profiles (id, user_id, store_name, bio)
VALUES ('${SELLER_ID}', '${USER_ID}', 'Store ${CASE_SUFFIX}', 'bio');
SQL
TOKEN="$(create_jwt "{\"id\":\"${USER_ID}\",\"email\":\"${USER_EMAIL}\",\"role\":\"SELLER\",\"status\":\"APPROVED\"}")"

# When
cat > "$PAYLOAD_FILE" <<EOF
{
  "title": "${PRODUCT_TITLE}",
  "description": "Stylish lamp",
  "category": "HOME",
  "price_cents": 4999,
  "stock_qty": 10,
  "photos": [
    "https://example.com/lamp1-${CASE_SUFFIX}.jpg",
    "https://example.com/lamp2-${CASE_SUFFIX}.jpg"
  ]
}
EOF
curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST \
  "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  --data @"$PAYLOAD_FILE" > "$STATUS_FILE"

# Then
STATUS="$(cat "$STATUS_FILE")"
[ "$STATUS" = "201" ]
grep -F '"sellerId":"'"$SELLER_ID"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"title":"'"$PRODUCT_TITLE"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"priceCents":4999' "$RESPONSE_FILE" >/dev/null
grep -F '"stockQty":10' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"ACTIVE"' "$RESPONSE_FILE" >/dev/null
grep -F '"visible":true' "$RESPONSE_FILE" >/dev/null
grep -F "https://example.com/lamp1-${CASE_SUFFIX}.jpg" "$RESPONSE_FILE" >/dev/null
grep -F "https://example.com/lamp2-${CASE_SUFFIX}.jpg" "$RESPONSE_FILE" >/dev/null
DB_ROW="$(psql "$DATABASE_URL" -At -c "SELECT seller_id || '|' || title || '|' || price_cents::text || '|' || stock_qty::text || '|' || status || '|' || visible::text FROM products WHERE title = '${PRODUCT_TITLE}';")"
[ "$DB_ROW" = "${SELLER_ID}|${PRODUCT_TITLE}|4999|10|ACTIVE|true" ]
echo "CODEVALID_TEST_ASSERTION_OK:approved_seller_creates_product_with_positive_stock"

# Cleanup
cleanup_db
