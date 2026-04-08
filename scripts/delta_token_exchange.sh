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
  # Also update HA input_text so the refresh page sees it immediately
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

log "Starting token exchange with code: ${CODE:0:20}..."

# Strip whitespace
CODE=$(echo "$CODE" | tr -d '[:space:]')

# Step 1: Call PostAuth - capture headers without following redirects
RESPONSE=$(curl -s -o /dev/null -D - \
  "https://device.deltafaucet.com/Auth/PostAuth?code=${CODE}&state=none" \
  -H "dfc-source: mobile" \
  -H "User-Agent: DFCatHome/2.6.0 CFNetwork/3860.400.51 Darwin/25.3.0" \
  --max-redirs 0 \
  2>&1)

# Step 2: Extract Location header
LOCATION=$(echo "$RESPONSE" | grep -i "^location:" | head -1 | tr -d '\r\n' | sed 's/^[Ll]ocation: *//')
log "Location header: ${LOCATION:0:80}..."

if [ -z "$LOCATION" ]; then
  # Check for HTTP status
  HTTP_STATUS=$(echo "$RESPONSE" | head -1)
  write_status "ERROR: No redirect from PostAuth. Response: ${HTTP_STATUS}. Code may be expired."
  exit 1
fi

# Step 3: Extract base64 payload
# URL: https://device.deltafaucet.com/#/auth/BASE64_ENCODED_JSON
BASE64_PAYLOAD=$(echo "$LOCATION" | sed -n 's|.*#/auth/\(.*\)|\1|p')

if [ -z "$BASE64_PAYLOAD" ]; then
  write_status "ERROR: No base64 payload in redirect URL"
  exit 1
fi

log "Base64 payload length: ${#BASE64_PAYLOAD}"

# Step 4: Decode base64
# Handle URL-safe base64 (- -> +, _ -> /)
# Also handle missing padding
PADDED="$BASE64_PAYLOAD"
case $(( ${#PADDED} % 4 )) in
  2) PADDED="${PADDED}==" ;;
  3) PADDED="${PADDED}=" ;;
esac

DECODED=$(echo "$PADDED" | tr '_-' '/+' | base64 -d 2>/dev/null)

if [ -z "$DECODED" ]; then
  write_status "ERROR: Failed to decode base64 payload"
  exit 1
fi

log "Decoded JSON: ${DECODED:0:100}..."

# Step 5: Extract accessToken
ACCESS_TOKEN=$(echo "$DECODED" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    token = data.get('accessToken', '')
    # Handle double encoding
    if token.startswith('\"'):
        token = json.loads(token)
    # Strip 'Bearer ' prefix if present
    if token.lower().startswith('bearer '):
        token = token[7:]
    print(token.strip())
except Exception as e:
    print('', file=sys.stdout)
    print(f'Parse error: {e}', file=sys.stderr)
" 2>>"$LOG_FILE")

if [ -z "$ACCESS_TOKEN" ]; then
  write_status "ERROR: Failed to extract accessToken from JSON"
  exit 1
fi

log "Token extracted, length: ${#ACCESS_TOKEN}"

# Validate JWT format (3 dot-separated segments)
DOT_COUNT=$(echo "$ACCESS_TOKEN" | tr -cd '.' | wc -c)
if [ "$DOT_COUNT" -ne 2 ]; then
  write_status "ERROR: Token doesn't look like a JWT (expected 2 dots, got ${DOT_COUNT})"
  exit 1
fi

# Step 6: Extract expiry from JWT payload
JWT_PAYLOAD=$(echo "$ACCESS_TOKEN" | cut -d. -f2)
# Add padding
case $(( ${#JWT_PAYLOAD} % 4 )) in
  2) JWT_PAYLOAD="${JWT_PAYLOAD}==" ;;
  3) JWT_PAYLOAD="${JWT_PAYLOAD}=" ;;
esac

EXP=$(echo "$JWT_PAYLOAD" | tr '_-' '/+' | base64 -d 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('exp', 0))
except:
    print(0)
" 2>/dev/null)

NOW=$(date +%s)
if [ "$EXP" -gt 0 ] 2>/dev/null; then
  DAYS_LEFT=$(( (EXP - NOW) / 86400 ))
  log "Token expires: exp=$EXP, days_left=$DAYS_LEFT"
else
  DAYS_LEFT="unknown"
  log "Could not parse token expiry"
fi

# Step 7: Back up and update secrets.yaml
cp "$SECRETS_FILE" "${SECRETS_FILE}.bak"
log "Backed up secrets.yaml"

if grep -q "^delta_token:" "$SECRETS_FILE"; then
  python3 -c "
import re
with open('$SECRETS_FILE', 'r') as f:
    content = f.read()
new_token = 'Bearer $ACCESS_TOKEN'
content = re.sub(
    r'^(delta_token:\s*).*$',
    r'\g<1>\"' + new_token + '\"',
    content,
    flags=re.MULTILINE
)
with open('$SECRETS_FILE', 'w') as f:
    f.write(content)
" 2>>"$LOG_FILE"

  if [ $? -ne 0 ]; then
    write_status "ERROR: Failed to update secrets.yaml (backup at secrets.yaml.bak)"
    exit 1
  fi
  log "Updated delta_token in secrets.yaml"
else
  echo "delta_token: \"Bearer ${ACCESS_TOKEN}\"" >> "$SECRETS_FILE"
  log "Appended delta_token to secrets.yaml"
fi

# Step 8: Update exp_ts in automations.yaml (for the expiry warning)
if [ "$EXP" -gt 0 ] 2>/dev/null; then
  if [ -f "/config/automations.yaml" ]; then
    python3 -c "
import re
with open('/config/automations.yaml', 'r') as f:
    content = f.read()
content = re.sub(r'exp_ts\s*=\s*\d+', 'exp_ts = $EXP', content)
with open('/config/automations.yaml', 'w') as f:
    f.write(content)
" 2>>"$LOG_FILE"
    log "Updated exp_ts in automations.yaml to $EXP"
  fi

  # Also update the template sensor if it's in configuration.yaml
  if grep -q "exp_ts" /config/configuration.yaml 2>/dev/null; then
    python3 -c "
import re
with open('/config/configuration.yaml', 'r') as f:
    content = f.read()
content = re.sub(r'exp_ts\s*=\s*\d+', 'exp_ts = $EXP', content)
with open('/config/configuration.yaml', 'w') as f:
    f.write(content)
" 2>>"$LOG_FILE"
    log "Updated exp_ts in configuration.yaml to $EXP"
  fi
fi

# Step 9: Calculate expiry date for display
EXPIRY_DATE=""
if [ "$EXP" -gt 0 ] 2>/dev/null; then
  EXPIRY_DATE=$(date -d "@$EXP" '+%B %d, %Y' 2>/dev/null || date -r "$EXP" '+%B %d, %Y' 2>/dev/null || echo "unknown")
fi

FINAL_STATUS="OK: Token refreshed. Expires ${EXPIRY_DATE} (${DAYS_LEFT} days). Backup at secrets.yaml.bak"
write_status "$FINAL_STATUS"

log "Token exchange complete"
echo "OK"