# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

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
