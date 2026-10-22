#!/usr/bin/env bash
# Manage the Telegram reminder bot from the Mac. Reads the service key from .env.local (never committed).
# Usage:
#   scripts/reminders.sh list
#   scripts/reminders.sh add  "label" "HH:MM" "0,1,2,3,4,5,6" "message"     # days: 0=Sun … 6=Sat
#   scripts/reminders.sh set  <id> time=HH:MM | days=1,2,3 | message="..." | enabled=true|false
#   scripts/reminders.sh rm   <id>
#   scripts/reminders.sh shift 60          # winter: every reminder fires 60 min later; 0 for summer
#   scripts/reminders.sh pause | resume
#   scripts/reminders.sh test "message"    # sends one message now
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env.local ] || { echo "missing .env.local"; exit 1; }
set -a; source .env.local; set +a
API="$VITE_SUPABASE_URL/rest/v1"
H=(-H "apikey: $SUPABASE_SERVICE_ROLE_KEY" -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" -H "Content-Type: application/json")
q() { curl -sS "${H[@]}" "$@"; }
jsonstr() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"; }
days_arr() { echo "[${1}]"; }

case "${1:-}" in
  list)
    q "$API/bot_reminders?select=id,label,time_ist,days,enabled,message&order=time_ist" | python3 -c '
import json,sys
rows=json.load(sys.stdin)
names="Sun Mon Tue Wed Thu Fri Sat".split()
for r in rows:
    d="daily" if len(r["days"])==7 else ",".join(names[i] for i in r["days"])
    print(f'"'"'{r["id"]:>3}  {r["time_ist"][:5]}  {"on " if r["enabled"] else "OFF"}  {d:<22} {r["label"]:<12} {r["message"]}'"'"')'
    echo; q "$API/bot_config?select=key,value&key=in.(shift_minutes,enabled)" ;;
  add)
    q -X POST "$API/bot_reminders" -H "Prefer: return=representation" \
      -d "{\"label\":$(jsonstr "$2"),\"time_ist\":\"$3\",\"days\":$(days_arr "$4"),\"message\":$(jsonstr "$5")}" ;;
  set)
    id="$2"; shift 2; body="{"
    for kv in "$@"; do k="${kv%%=*}"; v="${kv#*=}"
      case "$k" in time) body+="\"time_ist\":\"$v\",";; days) body+="\"days\":$(days_arr "$v"),";; message|label) body+="\"$k\":$(jsonstr "$v"),";; enabled) body+="\"enabled\":$v,";; *) echo "unknown field $k"; exit 1;; esac
    done
    body="${body%,}}"; q -X PATCH "$API/bot_reminders?id=eq.$id" -H "Prefer: return=representation" -d "$body" ;;
  rm)   q -X DELETE "$API/bot_reminders?id=eq.$2" -H "Prefer: return=representation" ;;
  shift) q -X POST "$API/bot_config" -H "Prefer: resolution=merge-duplicates,return=representation" -d "{\"key\":\"shift_minutes\",\"value\":\"$2\"}" ;;
  pause)  q -X POST "$API/bot_config" -H "Prefer: resolution=merge-duplicates,return=representation" -d '{"key":"enabled","value":"false"}' ;;
  resume) q -X POST "$API/bot_config" -H "Prefer: resolution=merge-duplicates,return=representation" -d '{"key":"enabled","value":"true"}' ;;
  test)  q -X POST "$API/rpc/bot_send" -d "{\"msg\":$(jsonstr "$2")}" ;;
  *) sed -n 2,11p "$0"; exit 1 ;;
esac
echo
