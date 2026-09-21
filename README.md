# Gunky

[![CI](https://github.com/romkey/pdxhackerspace-gunky/actions/workflows/ci.yml/badge.svg)](https://github.com/romkey/pdxhackerspace-gunky/actions/workflows/ci.yml)
[![Lint](https://github.com/romkey/pdxhackerspace-gunky/actions/workflows/lint.yml/badge.svg)](https://github.com/romkey/pdxhackerspace-gunky/actions/workflows/lint.yml)
[![Build](https://github.com/romkey/pdxhackerspace-gunky/actions/workflows/release.yml/badge.svg)](https://github.com/romkey/pdxhackerspace-gunky/actions/workflows/release.yml)
[![Ruby](https://img.shields.io/badge/Ruby-4.0.6-E67E22?logo=ruby&logoColor=white)](.ruby-version)
[![Rails](https://img.shields.io/badge/Rails-8.1.3.1-E67E22?logo=rubyonrails&logoColor=white)](Gemfile)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

*Pronounced the same way you pronounce "GIF."*

**G**unky **U**proots **N**asty [**K**ipple](#kipple), **Y**ay!

Gunky helps you figure out what to do with all that stuff piling up. Upload items, snap a photo, and let the community decide their fate through Slack polls:

- **I want this** — someone claims it
- **Keep it for the space** — keep it at the space
- **Trash it** — toss it

Items that nobody votes on get auto-killed after a week. Items with votes are resolved by an admin.

## Setup

### Prerequisites

- Docker and Docker Compose
- A Slack workspace with a bot app configured (see [Slack Setup](#slack-setup))

### Getting Started

```bash
cp .env.example .env
# Edit .env with your Slack credentials
# Optional: set TZ (for example, TZ=America/Los_Angeles) to control app timezone

docker compose up -d db redis
docker compose run --rm web bin/rails db:create db:migrate
docker compose up
```

The app will be available at http://localhost:3000.

### Receipt printing (optional)

Under **Settings → Thermal printer**, set the **CUPS printer queue** name from `lpstat -p` or `lpstat -a`. Item receipts are built as a PDF and submitted with the system **`lp -d`** command (the Docker image includes `cups-client`). If the app runs in a container, point it at your CUPS server with **`CUPS_SERVER`** (see `.env.example`).

### Slack Setup

1. Create a new Slack app at https://api.slack.com/apps
2. Under **OAuth & Permissions**, add the bot scopes: `chat:write`, `files:read`
3. Install the app to your workspace
4. Copy the **Bot User OAuth Token** to `SLACK_BOT_TOKEN` in `.env`
5. Optional: set `SLACK_USER_LOOKUP_TOKEN` to a token with `users:read` if you want name lookups separate from the bot token
6. Under **Interactivity & Shortcuts**, enable interactivity and set the request URL to `https://your-domain/slack/interactions`
7. Copy the **Signing Secret** from **Basic Information** to `SLACK_SIGNING_SECRET` in `.env`
8. Set `SLACK_CHANNEL_ID` to the channel where Gunky polls should be posted
9. Set `SLACK_LOST_FOUND_CHANNEL_ID` to the channel where lost+found items are posted (falls back to `SLACK_CHANNEL_ID` if unset)
10. Set `GUNKY_URL` and `LOST_FOUND_URL` to the public base URLs for each site (for example `https://gunky.example.org` and `https://lostfound.example.org`). The request host determines which site you see; unknown hosts are treated as Gunky.
11. Set `APP_HOST` for image URLs used in Slack messages (host or host:port). Optionally set `APP_PROTOCOL` (`http` or `https`).
12. Set `APP_INTERNAL_URL` to the full base URL used in expiry outcome Slack links (for example `https://gunky.example.org`).
13. Optional: set `SENTRY_DSN` (or `SENTRY_ENDPOINT`) to enable Sentry error reporting for web and Sidekiq.

### Lost+Found

Lost+Found is an optional phase before the normal Gunky giveaway flow. Upload an item on the lost+found domain and it posts to the lost+found Slack channel with a **This is mine** button. Unclaimed items are promoted to Gunky after the hold period (default 14 days, configurable under **Settings → Lost+Found**). Claimed items must be picked up within the pickup deadline (default 7 days) or they are promoted to Gunky as well. Promoted items enter the normal Gunky poll and are flagged as having been lost+found.

### Running Tests

Uses a separate Compose file (no app image build; source is bind-mounted; Postgres **18** and Redis **7** with `gunky-*` container names):

```bash
docker compose -f docker-compose.test.yml run --rm app
```

### Running Linter

```bash
docker compose -f docker-compose.test.yml run --rm lint
```

## Tech Stack

- Rails 8.1.3.1 / Ruby 4.0.6
- PostgreSQL 16 (development Compose) / PostgreSQL 18 (test Compose)
- Redis 7 / Sidekiq
- Bootstrap 5.3
- Stimulus / Turbo
- Prawn (receipt PDFs for `lp`)

## License

MIT — see [LICENSE](LICENSE).

## Kipple?

"Kipple is useless objects, like junk mail or match folders after you use the last match or gum wrappers or yesterday's homeopape. When nobody's around, kipple reproduces itself. For instance, if you go to bed leaving any kipple around your apartment, when you wake up the next morning there's twice as much of it. It always gets more and more."

"I see." The girl regarded him uncertainly, not knowing whether to believe him. Not sure if he meant it seriously.

"There's the First Law of Kipple," he said. "'Kipple drives out nonkipple.' Like Gresham's law about bad money. And in these apartments there's been nobody there to fight the kipple."

"So it has taken over completely," the girl finished. She nodded. "Now I understand."

"Your place, here," he said, "this apartment you've picked—it's too kipple-ized to live in. We can roll the kipple-factor back; we can do like I said, raid the other apts. But—" He broke off.

"But what?"

Isidore said, "We can't win."

"Why not?" The girl stepped into the hall, closing the door behind her; arms folded self-consciously before her small high breasts she faced him, eager to understand. Or so it appeared to him, anyhow. She was at least listening.

"No one can win against kipple," he said, "except temporarily and maybe in one spot, like in my apartment I've sort of created a stasis between the pressure of kipple and nonkipple, for the time being. But eventually I'll die or go away, and then the kipple will again take over. It's a universal principle operating throughout the universe; the entire universe is moving toward a final state of total, absolute kippleization."

*— Philip K. Dick, **Do Androids Dream of Electric Sheep?** (1968)*
