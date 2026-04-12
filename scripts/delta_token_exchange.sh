#!/bin/bash
# delta_token_exchange.sh
# Called by HA shell_command to exchange a Delta auth code for a new token.
# Place at: /config/scripts/delta_token_exchange.sh
# Make executable: chmod +x /config/scripts/delta_token_exchange.sh
#
# Usage: delta_token_exchange.sh <delta_auth_code>
#
# What it does:
#   1. Calls Delta PostAuth with the code
#   2. Extracts the base64-encoded token JSON from the 302 redirect
#   3. Decodes and extracts the accessToken (JWT)
#   4. Updates secrets.yaml with the new token
#   5. Updates the exp_ts in automations.yaml
#   6. Writes result to /config/www/delta_token_status.txt


CODE="$1"
SECRETS_FILE="/config/secrets.yaml"
STATUS_FILE="/config/www/delta_token_status.txt"
LOG_FILE="/config/www/delta_token_exchange.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

write_status() {
  echo "$1" > "$STATUS_FILE"
  log "STATUS: $1"
  # Push status to HA via Supervisor API
  curl -s -X POST \
    "http://supervisor/core/api/services/input_text/set_value" \
    -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"entity_id\": \"input_text.delta_token_status\", \"value\": \"$(echo "$1" | sed 's/"/\\"/g')\"}" \
    >/dev/null 2>&1
}

# Validate input
if [ -z "$CODE" ]; then
  write_status "ERROR: No auth code provided"
  exit 1
fi

log "Starting token exchange with code: $(echo "$CODE" | head -c 20)..."

# Strip whitespace
CODE=$(echo "$CODE" | tr -d '[:space:]')

# Step 1: Call PostAuth and capture headers (don't follow redirect)
HEADERS=$(curl -s -D - -o /dev/null \
  "https://device.deltafaucet.com/Auth/PostAuth?code=${CODE}&state=none" \
  -H "dfc-source: mobile" \
  -H "User-Agent: DFCatHome/2.6.0 CFNetwork/3860.400.51 Darwin/25.3.0" \
  --max-redirs 0 \
  2>/dev/null)

# Step 2: Extract Location header
LOCATION=$(echo "$HEADERS" | grep -i "^location:" | head -1 | sed 's/^[Ll]ocation: *//' | tr -d '\r\n')
log "Location header: $(echo "$LOCATION" | head -c 80)..."

if [ -z "$LOCATION" ]; then
  HTTP_STATUS=$(echo "$HEADERS" | head -1)
  write_status "ERROR: No redirect from PostAuth. ${HTTP_STATUS}"
  exit 1
fi

# Step 3: Extract base64 payload from URL
# URL: https://device.deltafaucet.com/#/auth/BASE64_ENCODED_JSON
BASE64_PAYLOAD=$(echo "$LOCATION" | sed -n 's|.*#/auth/||p')

if [ -z "$BASE64_PAYLOAD" ]; then
  write_status "ERROR: No base64 payload in redirect URL"
  exit 1
fi

log "Base64 payload length: $(echo -n "$BASE64_PAYLOAD" | wc -c | tr -d ' ')"

# Step 4: Fix base64 padding and decode
# Handle URL-safe base64
PADDED=$(echo "$BASE64_PAYLOAD" | tr '_-' '/+')
# Add padding
MOD=$(( $(echo -n "$PADDED" | wc -c | tr -d ' ') % 4 ))
if [ "$MOD" -eq 2 ]; then
  PADDED="${PADDED}=="
elif [ "$MOD" -eq 3 ]; then
  PADDED="${PADDED}="
fi

DECODED=$(echo "$PADDED" | base64 -d 2>/dev/null)

if [ -z "$DECODED" ]; then
  write_status "ERROR: Failed to decode base64 payload"
  exit 1
fi

log "Decoded JSON: $(echo "$DECODED" | head -c 100)..."

# Step 5: Extract accessToken from JSON
# The JSON structure is: {"ContentType":null,...,"Value":{"brand":"Delta","accessToken":"DOUBLE_ENCODED_JWT",...}}
# The accessToken may be double-encoded with escaped quotes like: \"eyJhbG...\"

# First extract everything after "accessToken":"
RAW_TOKEN=$(echo "$DECODED" | sed 's/.*"accessToken":"//')
# Now cut at the next unescaped quote - handle \" inside the value
# The token ends at "," or "} so find the pattern ","  or "}
# Use awk to properly handle this
ACCESS_TOKEN=$(echo "$RAW_TOKEN" | awk -F'","' '{print $1}' | awk -F'"}' '{print $1}')

# Remove any escaped quotes from double-encoding
ACCESS_TOKEN=$(echo "$ACCESS_TOKEN" | sed 's/\\"//g' | sed "s/\\\\//g")

# Strip "Bearer " prefix if present
case "$ACCESS_TOKEN" in
  Bearer\ *|bearer\ *) ACCESS_TOKEN=$(echo "$ACCESS_TOKEN" | sed 's/^[Bb]earer //');;
esac

ACCESS_TOKEN=$(echo "$ACCESS_TOKEN" | tr -d '[:space:]')

log "Extracted token preview: $(echo "$ACCESS_TOKEN" | head -c 50)..."

# Check if token is base64-encoded (starts with uppercase letters, no dots)
# A JWT starts with eyJ, but if double-encoded it starts with ZXlK or similar
DOT_CHECK=$(echo "$ACCESS_TOKEN" | tr -cd '.' | wc -c | tr -d ' ')
if [ "$DOT_CHECK" -eq 0 ]; then
  log "Token appears base64-encoded, decoding again..."
  # Add padding if needed
  TMOD=$(( $(echo -n "$ACCESS_TOKEN" | wc -c | tr -d ' ') % 4 ))
  TPADDED="$ACCESS_TOKEN"
  if [ "$TMOD" -eq 2 ]; then
    TPADDED="${TPADDED}=="
  elif [ "$TMOD" -eq 3 ]; then
    TPADDED="${TPADDED}="
  fi
  ACCESS_TOKEN=$(echo "$TPADDED" | tr '_-' '/+' | base64 -d 2>/dev/null)
  log "Double-decoded token preview: $(echo "$ACCESS_TOKEN" | head -c 50)..."
fi

ACCESS_TOKEN=$(echo "$ACCESS_TOKEN" | tr -d '[:space:]')

if [ -z "$ACCESS_TOKEN" ]; then
  write_status "ERROR: Failed to extract accessToken"
  exit 1
fi

log "Token extracted, length: $(echo -n "$ACCESS_TOKEN" | wc -c | tr -d ' ')"

# Validate JWT format (must contain exactly 2 dots)
DOT_COUNT=$(echo "$ACCESS_TOKEN" | tr -cd '.' | wc -c | tr -d ' ')
if [ "$DOT_COUNT" -ne 2 ]; then
  write_status "ERROR: Token not a valid JWT (expected 2 dots, got ${DOT_COUNT})"
  exit 1
fi

# Step 6: Extract expiry from JWT payload (middle segment)
JWT_PAYLOAD=$(echo "$ACCESS_TOKEN" | cut -d. -f2)
# Add padding
JMOD=$(( $(echo -n "$JWT_PAYLOAD" | wc -c | tr -d ' ') % 4 ))
if [ "$JMOD" -eq 2 ]; then
  JWT_PAYLOAD="${JWT_PAYLOAD}=="
elif [ "$JMOD" -eq 3 ]; then
  JWT_PAYLOAD="${JWT_PAYLOAD}="
fi

JWT_DECODED=$(echo "$JWT_PAYLOAD" | tr '_-' '/+' | base64 -d 2>/dev/null)
# Extract exp value using sed
EXP=$(echo "$JWT_DECODED" | sed 's/.*"exp"://' | sed 's/[^0-9].*//')

NOW=$(date +%s)
if [ -n "$EXP" ] && [ "$EXP" -gt 0 ] 2>/dev/null; then
  DAYS_LEFT=$(( (EXP - NOW) / 86400 ))
  log "Token exp=$EXP, days_left=$DAYS_LEFT"
else
  EXP=0
  DAYS_LEFT="unknown"
  log "Could not parse token expiry"
fi

# Step 7: Backup and update secrets.yaml
cp "$SECRETS_FILE" "${SECRETS_FILE}.bak"
log "Backed up secrets.yaml"

# Update delta_token line using sed
if grep -q "^delta_token:" "$SECRETS_FILE"; then
  sed -i "s|^delta_token:.*|delta_token: \"Bearer ${ACCESS_TOKEN}\"|" "$SECRETS_FILE"
  log "Updated delta_token in secrets.yaml"
else
  echo "delta_token: \"Bearer ${ACCESS_TOKEN}\"" >> "$SECRETS_FILE"
  log "Appended delta_token to secrets.yaml"
fi

# Step 8: Update exp_ts in automations.yaml and configuration.yaml
if [ "$EXP" -gt 0 ] 2>/dev/null; then
  for YAML_FILE in /config/automations.yaml /config/configuration.yaml; do
    if [ -f "$YAML_FILE" ] && grep -q "exp_ts" "$YAML_FILE"; then
      sed -i "s/exp_ts = [0-9]*/exp_ts = ${EXP}/" "$YAML_FILE"
      log "Updated exp_ts in $YAML_FILE to $EXP"
    fi
  done
fi

# Step 9: Calculate expiry date for display
EXPIRY_DATE="unknown"
if [ "$EXP" -gt 0 ] 2>/dev/null; then
  EXPIRY_DATE=$(date -d "@$EXP" '+%B %d, %Y' 2>/dev/null || date -r "$EXP" '+%B %d, %Y' 2>/dev/null || echo "unknown")
fi

FINAL_STATUS="OK: Token refreshed. Expires ${EXPIRY_DATE} (${DAYS_LEFT} days). Backup at secrets.yaml.bak"
write_status "$FINAL_STATUS"
log "Token exchange complete"
echo "OK"
