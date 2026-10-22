#!/usr/bin/env bash
# Create a family member's account. Usage: scripts/create-user.sh "Name" email@example.com
# Reads VITE_SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY from .env.local (never committed, never shipped).
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env.local ] || { echo "missing .env.local"; exit 1; }
set -a; source .env.local; set +a
NAME="${1:?name}"; EMAIL="${2:?email}"
PASS="$(LC_ALL=C tr -dc 'A-Za-z2-9' </dev/urandom | tr -d 'IlO0' | head -c 14)"
RESP="$(curl -sS -X POST "$VITE_SUPABASE_URL/auth/v1/admin/users" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\",\"email_confirm\":true,\"user_metadata\":{\"name\":\"$NAME\"}}")"
if echo "$RESP" | grep -q '"id"'; then
  echo "Created $NAME <$EMAIL>"; echo "Password: $PASS"; echo "(share these yourself; they are not stored anywhere)"
else
  echo "Failed: $RESP"; exit 1
fi
