# Changelog

All notable changes to Dispatch will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.1] — 2026-03-12

### Fixed
- **ASCII art missing top border on startup** — the `╔═══╗` top line was absent from
  both the startup banner and `--version` output. The heredoc block was being injected
  without the top border line, leaving the box visually open at the top. Fixed by
  ensuring the full box including `╔═══╗` is always included in the heredoc content
- **Stray `════` separator above ASCII art** — `banner()` was being called immediately
  before the startup heredoc, printing a `════` line directly above the `╔═══╗` border.
  Removed the redundant `banner()` call so the box renders cleanly on its own

---

## [1.0.0] — 2025-03-11

### Initial release

**Dispatch** is a transparent drop-in wrapper for rsync that adds SMTP email
notifications, webhook support, dead man's switch pinging, retry logic, lock files,
pre/post hooks, and HTML reports — with zero changes to your existing rsync syntax.

#### Features

- **Transparent wrapper** — installs to `/usr/local/bin/rsync`, takes PATH priority,
  auto-locates the real rsync binary and proxies all arguments. No syntax changes
- **SMTP email notifications** — styled HTML reports with colour-coded status header,
  sync summary table, transfer stats, and full rsync output. Supports Gmail, Office 365,
  SendGrid, and any SMTP provider. Multiple recipients via comma-separated `SMTP_TO`
- **HTML email** — multipart/alternative email with plain text fallback. HTML is the
  default. Use `--no-html-email` or `HTML_EMAIL=false` in config for plain text
- **Notify modes** — `always` | `failure` | `success` | `warnings` (exit 24 only)
- **Start notification** — optional `--notify-start` email when a sync begins
- **Webhook support** — POST JSON to any HTTP endpoint on completion. Works with Slack,
  Discord, ntfy.sh (with `Title` and `Tags` headers), and generic endpoints.
  `--webhook-on=always|failure|success` controls when webhooks fire
- **Dead man's switch** — `--ping-url=URL` GETs a URL on success only. Silent on
  failure. Works with Healthchecks.io, Uptime Kuma push monitors, and any URL-based
  heartbeat service
- **SMTP connection test** — `--smtp-test` sends a test email without running a sync.
  Reads live config, exits with curl's exit code for use in scripts
- **Self-update** — `sudo rsync --upgrade` fetches the latest installer from GitHub,
  runs a syntax check on it, then executes the update
- **Retry logic** — `--retry=N` and `--retry-delay=N` with configurable backoff.
  Exit code 24 (partial transfer) is treated as a warning, never triggers retry
- **Lock files** — prevents concurrent rsync jobs to the same destination. Stale locks
  are auto-detected and removed. `--no-lock` disables locking
- **Pre/post hooks** — `--pre-hook=/path` and `--post-hook=/path`. Post-hook receives
  `$RSYNC_EXIT_CODE`
- **Log files** — timestamped logs in `/var/log/dispatch/` with configurable rotation.
  `--logfile` per run or `LOG_ENABLED=true` in config
- **Stats parsing** — files transferred, total size, and transfer speed extracted from
  rsync output and surfaced in email summary. Captured in-memory so stats appear even
  without `--logfile`
- **Dry-run detection** — `--dry-run` / `-n` flagged clearly in all email subjects and
  bodies
- **Signal trapping** — `SIGINT` / `SIGTERM` trigger clean shutdown, lock release, and
  an `INTERRUPTED` notification
- **Config file support** — `/etc/dispatch.conf` (system-wide) and `~/.dispatch.conf`
  (per-user) sourced in order with cascading priority
- **Environment variable overrides** — `DISPATCH_HOST`, `DISPATCH_PORT`, `DISPATCH_USER`,
  `DISPATCH_PASS`, `DISPATCH_FROM`, `DISPATCH_TO`, `DISPATCH_TLS`
- **Quiet mode** — `--quiet` suppresses wrapper header/footer; rsync output unaffected
- **macOS compatible** — all grep patterns use `-oE | sed` pipelines, no GNU-only `-oP`
- **Auto-install rsync** — if no rsync binary is found in PATH, the wrapper detects the
  system package manager (`apt`, `dnf`, `yum`, `pacman`, `zypper`, `brew`) and installs
  rsync automatically
- **Versioned installer** — `install.sh` handles install, update, and uninstall.
  Detects existing config and preserves it on update. Interactive SMTP wizard on
  first install
- **Version bump utility** — `bump.sh` updates all version references atomically
  across all files, runs syntax checks, and optionally creates a git commit and tag
