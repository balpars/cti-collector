#!/bin/sh
# Passive and lightweight ransomware-news client.
#
# Consumes the ransomware.live recent-victims feed (they run the .onion
# crawlers; you just read clean JSON), remembers what it has seen in a flat
# file, and pushes only NEW victims to a webhook and/or a Telegram bot.
#
# Footprint: curl + jq run for a second or two, then exit. Nothing stays
# resident. Run it from cron. Requires only POSIX sh, curl, jq, base64.
#
# Usage:
#   ./cti.sh                 # fetch + notify (cron mode)
#   ./cti.sh some.json       # parse a local JSON file instead (offline test)
#
# Config via environment (all optional except a sink if you want alerts):
#   WEBHOOK_URL, WEBHOOK_TYPE(discord|slack|generic)
#   TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID
#   RANSOMWARE_LIVE_API, RANSOMWARE_LIVE_API_KEY, CTI_SEEN_FILE
#
# Works with both response shapes:
#   - free  api.ransomware.live/v2/recentvictims -> bare JSON array  [ ... ]
#   - pro   api-pro.ransomware.live/victims/recent -> object { "victims": [ ... ] }
# NOTE: the pro API matches the X-API-KEY header CASE-SENSITIVELY.
#
# Telegram messages are sent as parse_mode=HTML. All dynamic fields and the
# URL are HTML-escaped via jq @html so '&', '<', '>' can't break the message,
# and the link is rendered as a hidden "Read more" anchor.

set -eu

API="${RANSOMWARE_LIVE_API:-https://api.ransomware.live/v2/recentvictims}"
SEEN="${CTI_SEEN_FILE:-$HOME/.cti_seen}"
WEBHOOK_URL="${WEBHOOK_URL:-}"
WEBHOOK_TYPE="${WEBHOOK_TYPE:-discord}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
INPUT_FILE="${1:-}"

touch "$SEEN"

# 1. Get JSON: from a local file (testing) or the live feed.
if [ -n "$INPUT_FILE" ]; then
  get_json() { cat "$INPUT_FILE"; }
else
  get_json() {
    if [ -n "${RANSOMWARE_LIVE_API_KEY:-}" ]; then
      curl -fsS --max-time 60 -A "cti-shell/1.0" -H "X-API-KEY: $RANSOMWARE_LIVE_API_KEY" "$API"
    else
      curl -fsS --max-time 60 -A "cti-shell/1.0" "$API"
    fi
  }
fi

# 2. Normalize each victim into "uid_b64<space>msg_b64" (base64 keeps each
#    record on one line and free of delimiter collisions). The message is
#    HTML, with a fixed Company/Country/Ransom Group/Category layout, a short
#    Summary (leak-site description), and a hidden "Read more" link; every
#    interpolated value is @html-escaped.
records=$(get_json | jq -r '
  (if type=="object" then (.victims // .data // []) else . end)[] |
  ((.victim // .post_title // "unknown") + "|" +
   (.group // .group_name // "unknown") + "|" +
   (.discovered // .attackdate // .published // "")) as $uid |
  ((.permalink // .claim_url // .post_url // .url // .website // "")) as $link |
  ((.description // "") | gsub("\\s+";" ") | gsub("^ +| +$";"")) as $desc |
  ("Company: " + (.victim // .post_title // "unknown" | @html) + "\n" +
   "Country: " + ((.country // "") | if . == "" then "-" else . end | @html) + "\n" +
   "Ransom Group: " + (.group // .group_name // "unknown" | @html) + "\n" +
   "Category: " + ((.activity // .sector // "") | if . == "" then "-" else . end | @html) +
   (if $desc != "" then "\nSummary: " + (($desc | if length > 600 then .[0:600] + "..." else . end) | @html) else "" end) +
   (if $link != "" then "\n<a href=\"" + ($link | @html) + "\">Read more</a>" else "" end)
  ) as $msg |
  ($uid | @base64) + " " + ($msg | @base64)
')

# 3. Dedup against the seen-file and notify on anything new.
printf '%s\n' "$records" | while IFS=" " read -r uid_b64 msg_b64; do
  [ -z "$uid_b64" ] && continue
  if grep -qxF "$uid_b64" "$SEEN"; then
    continue
  fi
  echo "$uid_b64" >> "$SEEN"
  msg=$(printf '%s' "$msg_b64" | base64 -d)
  printf 'NEW %s\n' "$(printf '%s' "$msg" | tr '\n' ' ')"

  if [ -n "$WEBHOOK_URL" ]; then
    case "$WEBHOOK_TYPE" in
      slack|generic) payload=$(jq -nc --arg t "$msg" '{text:$t}') ;;
      *)             payload=$(jq -nc --arg t "$msg" '{content:$t}') ;;
    esac
    curl -fsS --max-time 30 -H 'Content-Type: application/json' \
      -d "$payload" "$WEBHOOK_URL" >/dev/null || echo "  ! webhook send failed" >&2
  fi

  if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
    payload=$(jq -nc --arg c "$TELEGRAM_CHAT_ID" --arg t "$msg" \
      '{chat_id:$c, text:$t, parse_mode:"HTML", disable_web_page_preview:true}')
    curl -fsS --max-time 30 -H 'Content-Type: application/json' \
      -d "$payload" "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      >/dev/null || echo "  ! telegram send failed" >&2
  fi
done

# Optional: keep the seen-file from growing forever (last 5000 ids is plenty).
if [ "$(wc -l < "$SEEN")" -gt 5000 ]; then
  tail -n 5000 "$SEEN" > "$SEEN.tmp" && mv "$SEEN.tmp" "$SEEN"
fi
