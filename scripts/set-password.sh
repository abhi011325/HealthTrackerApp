#!/usr/bin/env bash
# Reset a family member's password. Usage: scripts/set-password.sh email@example.com
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env.local; set +a
EMAIL="${1:?email}"
PASS="$(LC_ALL=C tr -dc 'A-Za-z2-9' </dev/urandom | tr -d 'IlO0' | head -c 14)"
ID="$(curl -sS "$VITE_SUPABASE_URL/auth/v1/admin/users?page=1&per_page=1000" -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const u=JSON.parse(s).users.find(u=>u.email===process.argv[1]);console.log(u?u.id:"")})' "$EMAIL")"
[ -n "$ID" ] || { echo "no user with that email"; exit 1; }
curl -sS -X PUT "$VITE_SUPABASE_URL/auth/v1/admin/users/$ID" -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" -H "Content-Type: application/json" \
  -d "{\"password\":\"$PASS\"}" >/dev/null
echo "New password for $EMAIL: $PASS"
