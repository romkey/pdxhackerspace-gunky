# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added

- Lost+Found navbar link **To move** listing items promoted to Gunky that still need to be physically moved off the Lost+Found shelf
- **Dismiss** button on each item to mark it moved, plus a **Select** mode with checkboxes and a bulk **Dismiss** for the checked items

## [0.20.4] - 2026-09-29

### Added

- Lost+Found navbar links for **Awaiting pickup** and **Picked up**, each listing only items in that state

### Changed

- Lost+Found index filter tab **Claimed** renamed to **Awaiting pickup** (legacy `claimed` URLs still work)

## [0.20.3] - 2026-09-29

### Added

- New Item form: always offers “Create Item & Add Another” and “Create Item, Print Receipt & Add Another”
- Retry AI description button under the description field when a photo is ready

### Changed

- Creating an item always returns to the New Item form (no separate Create-only submit)

## [0.20.2] - 2026-09-29

### Fixed

- OpenAI-compatible vision (LiteLLM): resize and convert photos to JPEG before sending, longer default read timeout, and `max_tokens` on chat/completions requests
- Item pages show an error when AI description fails after retries instead of staying on “AI is analyzing…”
- Production Docker image includes HEIF libraries so libvips can decode iPhone HEIC at AI describe time

### Changed

- Settings → AI Agent help text clarifies LiteLLM base URL vs `/chat/completions`
- Document AI request timeout env vars in `.env.example`

## [0.20.1] - 2026-09-27

### Fixed

- Activity log link in the navbar when `GUNKY_ADMIN_PASSWORD` is set (sign-in still required to view entries)
- Production Docker Compose now passes `GUNKY_ADMIN_PASSWORD` to web and Sidekiq

## [0.20.0] - 2026-09-27

### Added

- Slack thread reply pointing at similar items posted in the last 60 days, enabled with `DUPLICATE_HINTS_ENABLED`
- `gunky:duplicate_hints:report` rake task for tuning `DUPLICATE_HINT_MIN_RANK`

## [0.19.0] - 2026-09-27

### Added

- Admin activity log for uploads (IP and user agent), Slack traffic, and local AI attempts, with category filters and pagination (`GUNKY_ADMIN_PASSWORD`, `/admin/sign_in`)

## [0.18.3] - 2026-09-24

### Added

- Default lost+found location flag on locations (only one allowed), used to prefill lost+found uploads

## [0.18.2] - 2026-09-24

### Fixed

- iPhone HEIC/HEIF uploads are converted to JPEG at upload time so Slack photos and AI description work

## [0.18.1] - 2026-09-24

### Fixed

- Lost+Found items not posting to Slack when production env vars were missing from Docker Compose
- Lost+Found Slack posts failing silently when photo blocks were rejected or the bot was not in the channel
- Lost+Found site detection for mixed-case hostnames

## [0.18.0] - 2026-09-24

### Added

- Lost+Found phase: optional hold period before items enter the normal Gunky giveaway flow, with a separate site domain, Slack channel, and **This is mine** claim button
- Configurable hold and pickup windows under Settings → Lost+Found (defaults: 14 and 7 days)
- Automatic promotion of unclaimed or overdue claimed lost+found items to Gunky, flagged as previously lost+found
- Environment variables `GUNKY_URL`, `LOST_FOUND_URL`, and `SLACK_LOST_FOUND_CHANNEL_ID`
