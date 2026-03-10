# Gunky

*Pronounced the same way you pronounce "GIF."*

**G**unky **U**proots **N**asty [**K**ipple](#kipple), **Y**ay!

Gunky helps you figure out what to do with all that stuff piling up. Upload items, snap a photo, and let the community decide their fate through Slack polls:

- **Mine** — someone claims it
- **Foster** — keep it at the space
- **Kill** — toss it

Items that nobody votes on get auto-killed after a week. Items with votes are resolved by an admin.

## Setup

### Prerequisites

- Docker and Docker Compose
- A Slack workspace with a bot app configured (see [Slack Setup](#slack-setup))

### Getting Started

```bash
cp .env.example .env
# Edit .env with your Slack credentials

docker compose up -d db redis
docker compose run --rm web bin/rails db:create db:migrate
docker compose up
```

The app will be available at http://localhost:3000.

### Slack Setup

1. Create a new Slack app at https://api.slack.com/apps
2. Under **OAuth & Permissions**, add the bot scopes: `chat:write`, `files:read`
3. Install the app to your workspace
4. Copy the **Bot User OAuth Token** to `SLACK_BOT_TOKEN` in `.env`
5. Under **Interactivity & Shortcuts**, enable interactivity and set the request URL to `https://your-domain/slack/interactions`
6. Copy the **Signing Secret** from **Basic Information** to `SLACK_SIGNING_SECRET` in `.env`
7. Set `SLACK_CHANNEL_ID` to the channel where polls should be posted
8. Set `APP_HOST` for image URLs used in Slack messages (host or host:port). Optionally set `APP_PROTOCOL` (`http` or `https`).

### Running Tests

```bash
docker compose run --rm test
```

### Running Linter

```bash
docker compose run --rm test rubocop
```

## Tech Stack

- Rails 8.1.2 / Ruby 3.3
- PostgreSQL 16
- Redis 7 / Sidekiq
- Bootstrap 5.3
- Stimulus / Turbo

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
