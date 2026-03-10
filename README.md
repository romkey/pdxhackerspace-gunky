# Gunky

*Pronounced the same way you pronounce "GIF."*

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
