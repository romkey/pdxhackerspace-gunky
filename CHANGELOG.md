# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added

- Lost+Found phase: optional hold period before items enter the normal Gunky giveaway flow, with a separate site domain, Slack channel, and **This is mine** claim button
- Configurable hold and pickup windows under Settings → Lost+Found (defaults: 14 and 7 days)
- Automatic promotion of unclaimed or overdue claimed lost+found items to Gunky, flagged as previously lost+found
- Environment variables `GUNKY_URL`, `LOST_FOUND_URL`, and `SLACK_LOST_FOUND_CHANNEL_ID`
