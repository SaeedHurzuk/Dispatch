# Dispatch

**Your rsync jobs run silently. You only find out a backup failed when you check manually — or when the data is gone.**

Dispatch fixes that. It's a transparent drop-in wrapper that intercepts every rsync call on your system and sends you an email when it finishes — or when it fails. No syntax changes. No new commands to learn. Just install it and forget it.

```bash
curl -fsSL https://raw.githubusercontent.com/SaeedHurzuk/Dispatch/refs/heads/main/install.sh | sudo bash -s
```

---

## What it looks like

Your existing rsync commands are unchanged. The wrapper adds a header, runs the real rsync, then sends the email:

```
$ rsync -avhr --progress /home/ /mnt/backup/

╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║   ██████╗  ██╗ ███████╗ ██████╗   █████╗  ████████╗  ██████╗ ██╗  ██╗     ║
║   ██╔══██╗ ██║ ██╔════╝ ██╔══██╗ ██╔══██╗ ╚══██╔══╝ ██╔════╝ ██║  ██║     ║
║   ██║  ██║ ██║ ███████╗ ██████╔╝ ███████║    ██║    ██║      ███████║     ║
║   ██║  ██║ ██║ ╚════██║ ██╔═══╝  ██╔══██║    ██║    ██║      ██╔══██║     ║
║   ██████╔╝ ██║ ███████║ ██║      ██║  ██║    ██║    ╚██████╗ ██║  ██║     ║
║   ╚═════╝  ╚═╝ ╚══════╝ ╚═╝      ╚═╝  ╚═╝    ╚═╝     ╚═════╝ ╚═╝  ╚═╝     ║
║                                                                           ║
║                   ◄──── notify · rsync · deliver ────►                    ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝

[2025-03-11 02:14:33] Starting rsync...
[2025-03-11 02:14:33] Source      : /home/
[2025-03-11 02:14:33] Destination : /mnt/backup/
[2025-03-11 02:14:33] SMTP        : enabled → you@gmail.com

sending incremental file list
./
documents/report.pdf
photos/2025/

[✔] rsync completed in 1m 42s
[✔] Files transferred : 47
[✔] Total size        : 2.3 GB
[✔] Speed             : 23.1 MB/s
[✔] Email sent        → you@gmail.com
```

Meanwhile, in your inbox:

```
Subject: [dispatch] ✔ SUCCESS — /home/ → /mnt/backup/ (1m 42s)

Status    : SUCCESS
Source    : /home/
Dest      : /mnt/backup/
Started   : 2025-03-11 02:14:33
Duration  : 1m 42s
Files     : 47 transferred
Size      : 2.3 GB
Speed     : 23.1 MB/s
Exit code : 0
```

---

## Why not just write a wrapper script yourself?

You could. Five lines, done. But then you need to handle:

- SMTP auth, STARTTLS vs SSL, App Passwords
- Retry logic when the destination is temporarily unreachable
- Lock files so two cron jobs don't sync to the same destination simultaneously
- Log rotation so `/var/log/` doesn't fill up
- Interrupted job detection (Ctrl+C, kill, reboot mid-sync)
- Making it work correctly under `sudo`, cron, and every script that calls rsync directly

Dispatch handles all of that. One install, works system-wide, nothing else to touch.

---

## Zero syntax changes

Your existing commands, cron jobs, and scripts work exactly as before. The wrapper installs to `/usr/local/bin/rsync` which takes priority over `/usr/bin/rsync` in `$PATH`. Every rsync call on the system is transparently intercepted — the real binary is never touched.

```bash
# Your existing commands are completely unchanged
rsync -avhr --progress /home/ /mnt/backup/

# Add --smtp-enable to turn on notifications for any single run
rsync --smtp-enable -avhr --progress /home/ /mnt/backup/

# Or set SMTP_ENABLED=true in /etc/dispatch.conf to enable globally
```

---

## Works great on

- **Linux servers** — cron jobs, systemd timers, automated backup scripts
- **Synology NAS** — SSH in, run the one-liner, done
- **QNAP / TrueNAS** — same process, same result
- **Homelab** — finally know whether your nightly backup actually ran
- **Any system** where rsync runs unattended and you need to know when it fails

---

## Features

- **Transparent wrapper** — identical syntax to native rsync, all flags pass through untouched
- **SMTP notifications** — direct `curl` SMTP delivery, no `mail`/`sendmail`/`msmtp` required
- **HTML or plain text email** — styled HTML report card or clean plain text
- **Failure-only mode** — silent on success, notify only when something breaks
- **Multiple recipients** — comma-separated `SMTP_TO`
- **Retry logic** — configurable retry attempts with delay on failure
- **Lock file** — prevents concurrent rsync jobs to the same destination
- **Pre/post hooks** — run scripts before and after each sync
- **Timestamped log files** — optional, with automatic rotation
- **Config file support** — `/etc/dispatch.conf` or `~/.dispatch.conf`
- **Environment variable overrides** — ideal for CI/CD pipelines and automation
- **Dry-run aware** — detects `-n`/`--dry-run` and labels output and email accordingly
- **Signal trapping** — clean shutdown on `Ctrl+C` or `kill`, with optional interrupted notification
- **Parsed stats** — files transferred, size, and speed extracted into the email body
- **Auto-install** — detects your package manager and installs rsync if it's missing
- **Anti-recursion** — safely locates the real rsync binary, never calls itself

---

## Requirements

- `bash` 4.0+
- `curl` (for SMTP delivery)
- `awk` (for stats parsing)
- `rsync` — auto-installed if missing (`apt`, `dnf`, `yum`, `pacman`, `zypper`, or `brew`)

---

## Installation

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/SaeedHurzuk/Dispatch/refs/heads/main/install.sh | sudo bash -s
```

The installer will:
- Detect your OS and package manager
- Install `rsync`, `curl`, and `awk` if any are missing
- Copy the wrapper to `/usr/local/bin/rsync`
- Walk you through SMTP configuration interactively
- Create `/etc/dispatch.conf`, `/var/log/dispatch/`, and `/tmp/dispatch-locks/`
- Run a PATH check to confirm the wrapper is active

> **Note:** The `-s` flag is required when piping — it tells bash to read the script from stdin so any arguments after `--` are passed to the script rather than to bash itself.

### Clone and run

```bash
git clone https://github.com/SaeedHurzuk/Dispatch.git
cd Dispatch
sudo bash install.sh
```

### Manual install

```bash
sudo cp rsync /usr/local/bin/rsync
sudo chmod +x /usr/local/bin/rsync
```

### Verify

```bash
rsync --version
# Shows: Dispatch wrapper v1.0.3 + real rsync version below it
```

### Update

```bash
# Local
sudo bash install.sh --update

# Or via curl
curl -fsSL https://raw.githubusercontent.com/SaeedHurzuk/Dispatch/refs/heads/main/install.sh | sudo bash -s -- --update
```

> Existing config in `/etc/dispatch.conf` or `~/.dispatch.conf` is always preserved on update — SMTP setup is skipped if you're already configured.

### Uninstall

```bash
# Local
sudo bash install.sh --uninstall

# Or via curl
curl -fsSL https://raw.githubusercontent.com/SaeedHurzuk/Dispatch/refs/heads/main/install.sh | sudo bash -s -- --uninstall
```

---

## Configuration

### Option 1 — Config file (recommended)

Create `/etc/dispatch.conf` for system-wide config or `~/.dispatch.conf` for per-user:

```bash
# /etc/dispatch.conf or ~/.dispatch.conf
# All settings are optional — only include what you want to override.

# ── SMTP credentials ──────────────────────────────────────────────────────────
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=you@gmail.com
SMTP_PASS=your-app-password
SMTP_FROM=rsync@yourdomain.com
SMTP_TO=alerts@yourdomain.com     # Comma-separate for multiple: a@x.com,b@x.com
SMTP_TLS=starttls                 # starttls | ssl | none

# ── Behaviour ─────────────────────────────────────────────────────────────────
SMTP_ENABLED=true                 # Enable SMTP for every run without --smtp-enable
HTML_EMAIL=true                   # true (default) | false for plain text
NOTIFY_ON=always                  # always | failure | success | warnings
NOTIFY_START=false                # true to send an email when each sync begins

# ── Logging ───────────────────────────────────────────────────────────────────
LOG_ENABLED=false                 # true to write a log file for every run
LOG_DIR=/var/log/dispatch
LOG_ROTATE_KEEP=30                # Max log files to retain

# ── Retry ─────────────────────────────────────────────────────────────────────
RETRY_COUNT=0                     # Retries on failure (0 = disabled)
RETRY_DELAY=30                    # Seconds between retries

# ── Lock ──────────────────────────────────────────────────────────────────────
NO_LOCK=false                     # true to allow concurrent syncs to the same destination

# ── Webhooks ──────────────────────────────────────────────────────────────────
WEBHOOK_URL=                      # POST to this URL on completion (leave blank to disable)
WEBHOOK_ON=always                 # always | failure | success

# ── Dead man's switch ─────────────────────────────────────────────────────────
PING_URL=                         # GET this URL on success only (leave blank to disable)
```

### Option 2 — Environment variables

```bash
export DISPATCH_HOST=smtp.gmail.com
export DISPATCH_PORT=587
export DISPATCH_USER=you@gmail.com
export DISPATCH_PASS=your-app-password
export DISPATCH_FROM=rsync@yourdomain.com
export DISPATCH_TO=alerts@yourdomain.com
export DISPATCH_TLS=starttls
export DISPATCH_ENABLED=true
```

### Option 3 — Edit the script directly

The `CONFIGURATION` block at the top of the `rsync` script contains all defaults and is fully commented.

**Priority order:** script defaults → config file → environment variables → CLI flags

---

## Usage

```bash
# Standard rsync — all output shown, no email (default)
rsync -avhr --progress /source/ /dest/

# Enable email notification for this run
rsync --smtp-enable -avhr --progress /source/ /dest/

# Email only on failure — silent on success
rsync --smtp-enable --notify=failure -avhr --progress /source/ /dest/

# Email when sync starts AND when it finishes
rsync --smtp-enable --notify-start -avhr --progress /source/ /dest/

# Save a timestamped log file
rsync --logfile -avhr --progress /source/ /dest/

# Full production run — email + log + 3 retries on failure
rsync --smtp-enable --logfile --retry=3 --retry-delay=60 -avhr /source/ /dest/

# Dry run (auto-labelled in output and email)
rsync --smtp-enable -avhrn /source/ /dest/

# HTML email report
rsync --smtp-enable --logfile -avhr /source/ /dest/

# Pre and post hooks
rsync --pre-hook=/opt/hooks/pre.sh --post-hook=/opt/hooks/post.sh -avhr /source/ /dest/

# Multiple recipients (comma-separated in config or env var)
DISPATCH_TO="ops@company.com,backup@company.com" rsync --smtp-enable -av /src/ /dst/

# Allow concurrent runs to the same destination
rsync --no-lock -avhr /source/ /dest/

# Test your SMTP config without running a sync
rsync --smtp-test

# Send a webhook notification (Slack, Discord, ntfy.sh, generic HTTP)
rsync --webhook=https://hooks.slack.com/services/xxx -avhr /source/ /dest/

# Dead man's switch — ping Healthchecks.io on success
rsync --ping-url=https://hc-ping.com/your-uuid --smtp-enable -avhr /source/ /dest/

# HTML email report
rsync --smtp-enable --logfile -avhr /source/ /dest/
```

---

## Wrapper Flags Reference

All wrapper flags are stripped before reaching the real rsync binary.

| Flag | Default | Description |
|---|---|---|
| `--smtp-enable` | — | Enable SMTP notification for this run |
| `--smtp-disable` | — | Disable SMTP notification for this run |
| `--smtp-test` | — | Test SMTP connection and exit — no sync runs |
| `--notify=always` | `always` | Email on both success and failure |
| `--notify=failure` | — | Email only when rsync fails or is interrupted |
| `--notify=success` | — | Email only on successful completion |
| `--notify=warnings` | — | Email only on exit-code-24 (partial transfer) |
| `--notify-start` | off | Also send an email when the sync begins |
| `--html-email` | on | Send styled HTML email (default: on) |
| `--no-html-email` | — | Force plain text email |
| `--logfile` | off | Save output to timestamped log file |
| `--no-lock` | — | Disable lock file, allow concurrent runs |
| `--retry=N` | `0` | Retry up to N times on failure |
| `--retry-delay=N` | `30` | Seconds between retries |
| `--pre-hook=/path` | — | Script to run before rsync starts |
| `--post-hook=/path` | — | Script to run after rsync completes |
| `--webhook=URL` | — | POST notification to this URL on completion |
| `--webhook-on=EVENT` | `always` | When to fire webhook: `always` \| `failure` \| `success` |
| `--ping-url=URL` | — | GET this URL on success — dead man's switch / heartbeat |
| `--quiet` | off | Suppress wrapper header/footer (rsync output unaffected) |
| `--rsync-help` | — | Show the real rsync binary's own `--help` output |
| `--upgrade` | — | Self-update Dispatch to the latest version |
| `--version` | — | Show wrapper and rsync versions |
| `--help` | — | Show help message |

---

## SMTP Provider Quick Reference

| Provider | Host | Port | TLS |
|---|---|---|---|
| Gmail | `smtp.gmail.com` | `587` | `starttls` |
| Office 365 | `smtp.office365.com` | `587` | `starttls` |
| Outlook.com | `smtp-mail.outlook.com` | `587` | `starttls` |
| Yahoo | `smtp.mail.yahoo.com` | `587` | `starttls` |
| Fastmail | `smtp.fastmail.com` | `587` | `starttls` |
| Custom SSL | your host | `465` | `ssl` |
| Internal relay | your host | `25` | `none` |

> **Gmail note:** Standard password auth is blocked by Google. Generate an [App Password](https://myaccount.google.com/apppasswords) under your Google Account → Security → 2-Step Verification → App passwords.

---

## Log Files

Log files are only created when `--logfile` is passed. Saved to `LOG_DIR` (default: `/var/log/dispatch/`) with format:

```
rsync_20250311_143022.log
```

Rotation keeps the last 30 files by default. Adjust `LOG_ROTATE_KEEP` in the config.

---

## Pre/Post Hooks

Hook scripts receive the full rsync argument list as positional parameters (`$@`).

```bash
#!/usr/bin/env bash
# /opt/hooks/pre.sh — called before rsync
mount /mnt/backup 2>/dev/null || true
```

```bash
#!/usr/bin/env bash
# /opt/hooks/post.sh — called after rsync
umount /mnt/backup 2>/dev/null || true
```

```bash
chmod +x /opt/hooks/pre.sh /opt/hooks/post.sh
```

---

## Lock File Behaviour

A lock file is created in `/tmp/dispatch-locks/` keyed to the destination path, preventing two rsync jobs from running to the same destination simultaneously. Stale locks from crashed processes are detected and removed automatically.

Use `--no-lock` for destinations where concurrent runs are intentional.

---

## Webhooks

POST a notification to any URL when a sync completes. Works with Slack, Discord, ntfy.sh, and any generic HTTP endpoint.

```bash
# Any HTTP endpoint
rsync --webhook=https://your-endpoint.com/notify -avhr /src/ /dst/

# Slack (incoming webhook)
rsync --webhook=https://hooks.slack.com/services/T.../B.../xxx -avhr /src/ /dst/

# Discord (webhook URL)
rsync --webhook=https://discord.com/api/webhooks/xxx/yyy -avhr /src/ /dst/

# ntfy.sh (self-hosted or cloud)
rsync --webhook=https://ntfy.sh/your-topic -avhr /src/ /dst/

# Fire only on failure
rsync --webhook=https://ntfy.sh/alerts --webhook-on=failure -avhr /src/ /dst/
```

Set `WEBHOOK_URL=` and `WEBHOOK_ON=` in your config file to enable for all runs without passing the flag each time.

> **ntfy.sh note:** The wrapper sends a `Title: Dispatch <status>` header and `Tags: rsync,backup` which ntfy.sh uses for notification title and icons automatically.

---

## Dead Man's Switch

For cron jobs and scheduled backups, it's not enough to know when something *fails* — you also need to know if a job *stops running entirely*. A dead man's switch pings a URL on every successful sync. If the ping stops arriving, the monitoring service alerts you.

```bash
# Healthchecks.io
rsync --ping-url=https://hc-ping.com/your-uuid -avhr /src/ /dst/

# Uptime Kuma (push monitor)
rsync --ping-url=https://your-uptime-kuma/api/push/your-token -avhr /src/ /dst/
```

The ping only fires on `success` or `warnings` (exit 0 or 24). It is silently skipped on failure or interruption — which is exactly the point. Set `PING_URL=` in your config to enable for all runs.

---

## Troubleshooting

**rsync not found?**

```bash
sudo apt install rsync curl     # Debian / Ubuntu
sudo dnf install rsync curl     # RHEL / Fedora
sudo pacman -S rsync curl       # Arch
brew install rsync curl         # macOS
```

**Email not sending?** Run the debug curl command printed in the output:

```bash
curl -v --url smtp://smtp.gmail.com:587 --ssl-reqd \
  --user 'you@gmail.com:your-app-password' \
  --mail-from 'you@gmail.com' \
  --mail-rcpt 'recipient@example.com'
```

**Wrong rsync being called?**

```bash
which rsync               # should be /usr/local/bin/rsync (wrapper)
/usr/bin/rsync --version  # the real binary
```

**Lock file stuck?**

```bash
ls /tmp/dispatch-locks/   # view active locks
rm /tmp/dispatch-locks/*  # clear all locks manually
```

---

## License

MIT — see [LICENSE](LICENSE) for full text.

---

## Contributing

Pull requests are welcome. For significant changes, please open an issue first.
