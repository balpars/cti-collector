# ransomware.live → Telegram (passive CTI alerter)

A tiny, dependency-light shell client that watches the
[ransomware.live](https://www.ransomware.live) recent-victims feed and pushes
**only new** victim disclosures to a Telegram bot (and/or a Discord/Slack
webhook).

It is **passive and defensive**: it reads a public API, remembers what it has
already seen in a flat file, and exits. Nothing stays resident — `curl` + `jq`
run for a second under cron and quit, so it's happy on a 256 MB VPS.

```
Company: huashan.com.cn
Country: CN
Ransom Group: krybit
Category: Not Found
Summary: Shantou Huashan Electronic Devices Co., Ltd. is a Chinese manufacturer of…
Read more            ← clickable link to the ransomware.live page
```

## Features

- **New-only alerts** — dedupes against a seen-file (`victim|group|discovered`), so you never get repeats or a backlog flood.
- **Clean HTML cards** — fixed `Company / Country / Ransom Group / Category / Summary` layout with a hidden "Read more" link. Every field and URL is HTML-escaped, so odd characters can't break the message.
- **Free or Pro API** — works with the keyless free endpoint *or* the `X-API-KEY` pro endpoint (handles both the array and `{"victims":[…]}` response shapes).
- **Multiple sinks** — Telegram and a generic/Discord/Slack webhook, either or both.
- **Offline test mode** — point it at a saved JSON file instead of the network.

## Requirements

POSIX `sh`, `curl`, `jq`, `base64`. On Debian/Ubuntu only `jq` is usually missing:

```sh
sudo apt-get install -y jq
```

## Configuration

All via environment variables (see `cti.env.example`):

| Variable | Required | Description |
|----------|----------|-------------|
| `TELEGRAM_BOT_TOKEN` | for Telegram | Bot token from [@BotFather](https://t.me/BotFather) |
| `TELEGRAM_CHAT_ID` | for Telegram | Your numeric chat ID (DM the bot once, then check `getUpdates`, or ask [@userinfobot](https://t.me/userinfobot)) |
| `WEBHOOK_URL` | for webhook | Discord/Slack/generic webhook URL |
| `WEBHOOK_TYPE` | no | `discord` (default), `slack`, or `generic` |
| `RANSOMWARE_LIVE_API` | no | Feed URL. Defaults to the free endpoint. |
| `RANSOMWARE_LIVE_API_KEY` | no | Pro API key, sent as the `X-API-KEY` header |
| `CTI_SEEN_FILE` | no | Dedup state file (default `~/.cti_seen`) |

You need at least one sink (Telegram or webhook) to get alerts.

> **Free vs Pro endpoint**
> - Free (no key): `https://api.ransomware.live/v2/recentvictims`
> - Pro (key):     `https://api-pro.ransomware.live/victims/recent`
>
> ⚠️ The pro API matches the `X-API-KEY` header **case-sensitively** — a
> mixed-case header silently returns `403 Invalid API key`. This script sends
> it correctly; just be aware if you test by hand.

## Usage

```sh
# offline sanity check against a saved response (no network, no sends)
./cti.sh sample.json

# live: fetch + notify
set -a; . ./cti.env; set +a
./cti.sh
```

**First run will alert on every current victim.** To avoid that, seed the
seen-file silently once (run it with the sink variables unset), then enable the
sinks.

## Run it on a schedule (cron)

A wrapper keeps the crontab clean:

```sh
# run.sh
#!/bin/sh
. /opt/cti/cti.env
exec /opt/cti/cti.sh "$@"
```

```cron
# every 15 minutes
*/15 * * * * /opt/cti/run.sh >> /opt/cti/cti.log 2>&1
```

Keep `cti.env` private: `chmod 600 cti.env` (it holds your bot token / API key).

## Notes

- Consumes already-public disclosures. Keep usage to observing and protecting —
  don't redistribute or act on leaked data.
- The bot token and API key are credentials: never commit `cti.env`. Only
  `cti.env.example` belongs in git.

## License

MIT
