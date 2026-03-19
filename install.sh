#!/usr/bin/env bash
# =============================================================================
# install.sh — Interactive installer for Dispatch
# GitHub: https://github.com/SaeedHurzuk/Dispatch
#
# Usage:
#   sudo bash install.sh              # Interactive install
#   sudo bash install.sh --uninstall  # Remove Dispatch
#   sudo bash install.sh --update     # Update to latest version
#
# One-liners (note: pass -s to bash so args reach the script, not bash itself):
#   curl -fsSL https://raw.githubusercontent.com/SaeedHurzuk/Dispatch/refs/heads/main/install.sh | sudo bash -s
#   curl -fsSL https://raw.githubusercontent.com/SaeedHurzuk/Dispatch/refs/heads/main/install.sh | sudo bash -s -- --update
#   curl -fsSL https://raw.githubusercontent.com/SaeedHurzuk/Dispatch/refs/heads/main/install.sh | sudo bash -s -- --uninstall
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# CONFIGURATION
# =============================================================================
WRAPPER_VERSION="1.0.2"
INSTALL_DIR="/usr/local/bin"
WRAPPER_NAME="rsync"
WRAPPER_DST="${INSTALL_DIR}/${WRAPPER_NAME}"
REAL_RSYNC=""
BACKUP_SUFFIX=".pre-dispatch"
CONFIG_FILE_SYSTEM="/etc/dispatch.conf"
LOG_DIR="/var/log/dispatch"
LOCK_DIR="/tmp/dispatch-locks"
REPO_RAW_URL="https://raw.githubusercontent.com/SaeedHurzuk/Dispatch/refs/heads/main/rsync"

# =============================================================================
# COLOURS
# =============================================================================
# Colours — check /dev/tty for terminal detection so colours work
# correctly even when the script is piped via curl | bash
if [ -t 1 ] || [ -t 2 ] || { [ -e /dev/tty ] && tty -s 2>/dev/null; }; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
  CYAN=$'\033[0;36m'; BLUE=$'\033[0;34m'; BOLD=$'\033[1m'
  DIM=$'\033[2m'; RESET=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BLUE=''; BOLD=''; DIM=''; RESET=''
fi

# =============================================================================
# HELPERS
# =============================================================================
log()     { echo -e "${CYAN}[$(date '+%H:%M:%S')]${RESET} $*"; }
info()    { echo -e "${BLUE}  →${RESET} $*"; }
success() { echo -e "${GREEN}  [✔]${RESET} $*"; }
warn()    { echo -e "${YELLOW}  [⚠]${RESET} $*"; }
error()   { echo -e "${RED}  [✘]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }
divider() { echo -e "${DIM}  ────────────────────────────────────────────${RESET}"; }

banner() {
  echo ""
  echo -e "${CYAN}"
  cat << 'ASCIIART'
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
ASCIIART
  echo -e "${RESET}"
  echo -e "  ${BOLD}$1${RESET}  —  v${WRAPPER_VERSION}"
  echo -e "${DIM}  ────────────────────────────────────────────────────────────${RESET}"
  echo ""
}

# Prompt with a default value shown
# Usage: prompt_input "Label" "default_value" [secret]
# Reads from /dev/tty directly so it works correctly when piped via curl | bash
prompt_input() {
  local label="$1"
  local default="${2:-}"
  local secret="${3:-}"
  local value=""
  local prompt_str

  if [[ -n "$default" ]]; then
    prompt_str="  ${BOLD}${label}${RESET} ${DIM}[${default}]${RESET}: "
  else
    prompt_str="  ${BOLD}${label}${RESET}: "
  fi

  if [[ "$secret" == "secret" ]]; then
    read -rsp "$prompt_str" value </dev/tty
    echo "" >/dev/tty
  else
    read -rp "$prompt_str" value </dev/tty
  fi

  # Use default if empty
  echo "${value:-$default}"
}

# Yes/no prompt — returns 0 for yes, 1 for no
# Usage: prompt_yn "Question" "y"
# Reads from /dev/tty directly so it works correctly when piped via curl | bash
prompt_yn() {
  local label="$1"
  local default="${2:-n}"
  local yn_hint
  yn_hint="$( [[ "$default" == "y" ]] && echo "${BOLD}Y${RESET}/n" || echo "y/${BOLD}N${RESET}" )"
  local answer

  read -rp "  ${BOLD}${label}${RESET} [${yn_hint}]: " answer </dev/tty
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[Yy]$ ]]
}

# =============================================================================
# ROOT CHECK
# =============================================================================
check_root() {
  if [[ "$EUID" -ne 0 ]]; then
    die "This installer must be run as root. Try: sudo bash install.sh"
  fi
}

# =============================================================================
# OS + PACKAGE MANAGER DETECTION
# =============================================================================
detect_os() {
  OS="unknown"
  PKG_MANAGER="unknown"
  PRETTY_NAME="Unknown Linux"

  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    OS="${ID:-unknown}"
    PRETTY_NAME="${PRETTY_NAME:-$OS}"
  fi

  if   command -v apt-get &>/dev/null; then PKG_MANAGER="apt"
  elif command -v dnf     &>/dev/null; then PKG_MANAGER="dnf"
  elif command -v yum     &>/dev/null; then PKG_MANAGER="yum"
  elif command -v pacman  &>/dev/null; then PKG_MANAGER="pacman"
  elif command -v zypper  &>/dev/null; then PKG_MANAGER="zypper"
  elif command -v brew    &>/dev/null; then PKG_MANAGER="brew"
  fi
}

# =============================================================================
# DEPENDENCY INSTALLATION
# =============================================================================
DEPS_TO_INSTALL=()

check_deps() {
  echo -e "\n${BOLD}  Checking dependencies...${RESET}"
  divider

  local all_good=true

  for dep in rsync curl awk; do
    if command -v "$dep" &>/dev/null; then
      success "$dep — found ($(command -v "$dep"))"
    else
      warn "$dep — not found"
      DEPS_TO_INSTALL+=("$dep")
      all_good=false
    fi
  done

  if $all_good; then
    echo ""
    success "All dependencies satisfied."
    return 0
  fi

  echo ""
  warn "Missing: ${DEPS_TO_INSTALL[*]}"

  if [[ "$PKG_MANAGER" == "unknown" ]]; then
    die "No supported package manager found. Please manually install: ${DEPS_TO_INSTALL[*]}"
  fi

  info "Will install via: ${PKG_MANAGER}"
  echo ""
}

install_deps() {
  [[ ${#DEPS_TO_INSTALL[@]} -eq 0 ]] && return 0

  log "Installing: ${DEPS_TO_INSTALL[*]}..."

  case "$PKG_MANAGER" in
    apt)
      apt-get update -qq
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${DEPS_TO_INSTALL[@]}"
      ;;
    dnf)    dnf install -y -q "${DEPS_TO_INSTALL[@]}" ;;
    yum)    yum install -y -q "${DEPS_TO_INSTALL[@]}" ;;
    pacman) pacman -Sy --noconfirm "${DEPS_TO_INSTALL[@]}" ;;
    zypper) zypper install -y "${DEPS_TO_INSTALL[@]}" ;;
    brew)   sudo -u "${SUDO_USER:-$USER}" brew install "${DEPS_TO_INSTALL[@]}" ;;
    *)      die "Cannot auto-install. Please manually install: ${DEPS_TO_INSTALL[*]}" ;;
  esac

  # Verify everything installed correctly
  local failed=()
  for dep in "${DEPS_TO_INSTALL[@]}"; do
    command -v "$dep" &>/dev/null || failed+=("$dep")
  done

  [[ ${#failed[@]} -gt 0 ]] && die "Installation failed for: ${failed[*]}"

  success "Dependencies installed: ${DEPS_TO_INSTALL[*]}"
}

# =============================================================================
# LOCATE REAL RSYNC
# =============================================================================
find_real_rsync() {
  while IFS= read -r -d ':' dir; do
    dir="${dir%/}"
    [[ -z "$dir" ]] && continue
    [[ "$dir" == "$INSTALL_DIR" ]] && continue
    if [[ -x "$dir/rsync" ]]; then
      REAL_RSYNC="$dir/rsync"
      break
    fi
  done <<< "${PATH}:"

  if [[ -z "$REAL_RSYNC" ]]; then
    for fallback in /usr/bin/rsync /bin/rsync /opt/homebrew/bin/rsync; do
      [[ -x "$fallback" ]] && { REAL_RSYNC="$fallback"; break; }
    done
  fi

  if [[ -z "$REAL_RSYNC" ]]; then
    warn "Real rsync binary not found — attempting to install rsync now..."
    install_deps
    # Re-search after install
    for fallback in /usr/bin/rsync /bin/rsync /opt/homebrew/bin/rsync; do
      if [[ -x "$fallback" ]]; then
        REAL_RSYNC="$fallback"
        break
      fi
    done
    [[ -z "$REAL_RSYNC" ]] && die "rsync was installed but binary still not found. Check your PATH."
    success "rsync installed and located at: $REAL_RSYNC"
  fi
}

# =============================================================================
# VERIFY WRAPPER INTEGRITY
# =============================================================================
verify_wrapper() {
  local path="$1"
  [[ ! -f "$path" ]] && die "Wrapper not found: $path"
  [[ ! -s "$path" ]] && die "Wrapper is empty: $path"
  head -1 "$path" | grep -q 'bash'    || die "Wrapper is not a bash script."
  grep -q 'SELF_DIR' "$path"          || die "Wrapper missing anti-recursion logic — file may be corrupt."
  success "Wrapper integrity check passed"
}

# =============================================================================
# EXISTING CONFIG DETECTION
# =============================================================================
# Returns 0 (true) if a config file exists and has a non-placeholder SMTP_HOST
config_is_filled() {
  local conf=""
  # Prefer system-wide config; fall back to user config
  if [[ -f "$CONFIG_FILE_SYSTEM" ]]; then
    conf="$CONFIG_FILE_SYSTEM"
  elif [[ -f "${HOME}/.dispatch.conf" ]]; then
    conf="${HOME}/.dispatch.conf"
  else
    return 1  # no config file at all
  fi

  local host
  host=$(grep -E '^SMTP_HOST=' "$conf" 2>/dev/null | cut -d= -f2- | tr -d '"' | tr -d "'" | xargs)

  # Filled = host is set AND is not the installer placeholder
  if [[ -n "$host" && "$host" != "smtp.example.com" ]]; then
    return 0
  fi
  return 1
}

# =============================================================================
# INTERACTIVE SMTP SETUP
# =============================================================================
SMTP_ENABLED_CFG="false"
SMTP_HOST_CFG=""
SMTP_PORT_CFG=""
SMTP_USER_CFG=""
SMTP_PASS_CFG=""
SMTP_FROM_CFG=""
SMTP_TO_CFG=""
SMTP_TLS_CFG=""

smtp_provider_hint() {
  echo ""
  echo -e "  ${DIM}Provider quick reference:${RESET}"
  echo -e "  ${DIM}  Gmail       → smtp.gmail.com        : 587  (starttls + App Password)${RESET}"
  echo -e "  ${DIM}  Office 365  → smtp.office365.com    : 587  (starttls)${RESET}"
  echo -e "  ${DIM}  Outlook.com → smtp-mail.outlook.com : 587  (starttls)${RESET}"
  echo -e "  ${DIM}  Yahoo       → smtp.mail.yahoo.com   : 587  (starttls)${RESET}"
  echo -e "  ${DIM}  Custom SSL  → your.host             : 465  (ssl)${RESET}"
  echo -e "  ${DIM}  Internal    → your.relay            : 25   (none)${RESET}"
  echo ""
}

configure_smtp() {
  echo ""
  echo -e "${BOLD}  ✉  SMTP Notification Setup${RESET}"
  divider
  echo ""

  if ! prompt_yn "Enable SMTP email notifications?" "n"; then
    echo ""
    info "SMTP skipped — you can configure it later by editing:"
    info "$CONFIG_FILE_SYSTEM"
    echo ""
    SMTP_ENABLED_CFG="false"
    return 0
  fi

  SMTP_ENABLED_CFG="true"
  echo ""
  success "SMTP enabled. Let's configure your mail server."
  smtp_provider_hint
  divider
  echo ""

  # ── SMTP Host ──────────────────────────────────────────────────────────────
  SMTP_HOST_CFG=$(prompt_input "SMTP Host" "smtp.gmail.com")

  # ── SMTP Port ──────────────────────────────────────────────────────────────
  SMTP_PORT_CFG=$(prompt_input "SMTP Port" "587")

  # ── TLS Mode ───────────────────────────────────────────────────────────────
  echo ""
  echo -e "  ${BOLD}TLS Mode${RESET} ${DIM}— starttls (587) | ssl (465) | none (25)${RESET}"
  SMTP_TLS_CFG=$(prompt_input "TLS Mode" "starttls")

  # Normalise and validate
  SMTP_TLS_CFG="${SMTP_TLS_CFG,,}"  # lowercase
  if [[ ! "$SMTP_TLS_CFG" =~ ^(starttls|ssl|none)$ ]]; then
    warn "Unrecognised TLS mode '${SMTP_TLS_CFG}'. Defaulting to starttls."
    SMTP_TLS_CFG="starttls"
  fi

  echo ""
  divider

  # ── Credentials ────────────────────────────────────────────────────────────
  SMTP_USER_CFG=$(prompt_input "SMTP Username (email)" "")
  SMTP_PASS_CFG=$(prompt_input "SMTP Password / App Password" "" "secret")

  echo ""
  divider

  # ── From / To ──────────────────────────────────────────────────────────────
  SMTP_FROM_CFG=$(prompt_input "From address" "${SMTP_USER_CFG}")

  echo ""
  echo -e "  ${DIM}Tip: separate multiple recipients with commas${RESET}"
  SMTP_TO_CFG=$(prompt_input "Send notifications to" "${SMTP_USER_CFG}")

  # ── Notify mode ────────────────────────────────────────────────────────────
  echo ""
  divider
  echo ""
  echo -e "  ${BOLD}When should notifications be sent?${RESET}"
  echo -e "  ${DIM}  1) Always — on success and failure (default)${RESET}"
  echo -e "  ${DIM}  2) On failure only${RESET}"
  echo ""

  local notify_mode
  notify_mode=$(prompt_input "Choice" "1")

  case "$notify_mode" in
    2) SMTP_ON_FAILURE_ONLY_CFG="true"  ;;
    *) SMTP_ON_FAILURE_ONLY_CFG="false" ;;
  esac

  # ── Test SMTP connection ───────────────────────────────────────────────────
  echo ""
  divider
  echo ""

  if prompt_yn "Test SMTP connection now?" "y"; then
    echo ""
    log "Testing SMTP connection to ${SMTP_HOST_CFG}:${SMTP_PORT_CFG}..."

    local tls_flag=""
    case "$SMTP_TLS_CFG" in
      starttls) tls_flag="--ssl-reqd" ;;
      ssl)      tls_flag="--ssl"      ;;
      none)     tls_flag=""           ;;
    esac

    local test_exit=0
    # shellcheck disable=SC2086
    curl --silent --show-error --connect-timeout 10 \
      --url "smtp://${SMTP_HOST_CFG}:${SMTP_PORT_CFG}" \
      ${tls_flag} \
      --user "${SMTP_USER_CFG}:${SMTP_PASS_CFG}" \
      --mail-from "${SMTP_FROM_CFG}" \
      --mail-rcpt "${SMTP_TO_CFG}" \
      --upload-file - <<< $'Subject: Dispatch connection test\r\n\r\nSMTP connection test from Dispatch installer.' \
      && test_exit=0 || test_exit=$?

    if [[ "$test_exit" -eq 0 ]]; then
      success "SMTP connection test passed — check your inbox at ${SMTP_TO_CFG}"
    else
      warn "SMTP test failed (curl exit: ${test_exit})"
      warn "Check your credentials and server settings."
      echo ""
      if ! prompt_yn "Continue installation anyway?" "y"; then
        die "Installation aborted. Fix SMTP settings and re-run the installer."
      fi
    fi
  fi

  echo ""
  success "SMTP configuration complete."
}

# =============================================================================
# WRITE CONFIG FILE
# =============================================================================
write_config() {
  cat > "$CONFIG_FILE_SYSTEM" << CONF
# Dispatch system configuration
# /etc/dispatch.conf
#
# Generated by installer on $(date)
# Override per-user in ~/.dispatch.conf
# Override per-run via CLI flags or environment variables.
#
# Priority: script defaults → this file → ~/.dispatch.conf → env vars → CLI flags

# ── SMTP ──────────────────────────────────────────────────────────────────────
SMTP_ENABLED=${SMTP_ENABLED_CFG}
SMTP_HOST=${SMTP_HOST_CFG}
SMTP_PORT=${SMTP_PORT_CFG}
SMTP_USER=${SMTP_USER_CFG}
SMTP_PASS=${SMTP_PASS_CFG}
SMTP_FROM=${SMTP_FROM_CFG}
SMTP_TO=${SMTP_TO_CFG}
SMTP_TLS=${SMTP_TLS_CFG}

# ── Logging ───────────────────────────────────────────────────────────────────
LOG_DIR=${LOG_DIR}
CONF

  chmod 0640 "$CONFIG_FILE_SYSTEM"
  success "Config written: $CONFIG_FILE_SYSTEM"
}

# =============================================================================
# BACKUP EXISTING WRAPPER
# =============================================================================
backup_existing() {
  if [[ -f "$WRAPPER_DST" ]]; then
    local backup="${WRAPPER_DST}${BACKUP_SUFFIX}"
    cp "$WRAPPER_DST" "$backup"
    info "Existing file backed up to: $backup"
  fi
}

# =============================================================================
# INSTALL
# =============================================================================
do_install() {
  banner "Installer"

  check_root
  detect_os

  echo -e "  ${BOLD}System${RESET}  : ${PRETTY_NAME}"
  echo -e "  ${BOLD}Package manager${RESET}: ${PKG_MANAGER}"
  echo ""

  # ── Dependencies ────────────────────────────────────────────────────────────
  check_deps
  install_deps

  # ── Find real rsync ─────────────────────────────────────────────────────────
  find_real_rsync
  success "Real rsync found: $REAL_RSYNC"

  # ── Wrapper source ──────────────────────────────────────────────────────────
  echo ""
  echo -e "${BOLD}  Installing wrapper...${RESET}"
  divider

  local wrapper_src=""
  local tmp_wrapper=""

  if [[ -f "$(dirname "${BASH_SOURCE[0]}")/rsync" ]]; then
    wrapper_src="$(dirname "${BASH_SOURCE[0]}")/rsync"
    info "Using local file: $wrapper_src"
  elif command -v curl &>/dev/null; then
    info "Downloading from: $REPO_RAW_URL"
    tmp_wrapper=$(mktemp /tmp/dispatch-wrapper.XXXXXX)
    curl -fsSL "$REPO_RAW_URL" -o "$tmp_wrapper" \
      || die "Download failed. Check your internet connection or clone the repo manually."
    wrapper_src="$tmp_wrapper"
    success "Download complete."
  else
    die "No local wrapper found and curl unavailable. Clone the repo and run from within it."
  fi

  verify_wrapper "$wrapper_src"
  backup_existing

  install -m 0755 "$wrapper_src" "$WRAPPER_DST"
  [[ -n "$tmp_wrapper" ]] && rm -f "$tmp_wrapper"
  success "Wrapper installed: $WRAPPER_DST"

  # ── Directories ─────────────────────────────────────────────────────────────
  mkdir -p "$LOG_DIR";  chmod 1777 "$LOG_DIR"
  mkdir -p "$LOCK_DIR"; chmod 1777 "$LOCK_DIR"
  success "Directories ready: $LOG_DIR, $LOCK_DIR"

  # ── SMTP setup / config write ────────────────────────────────────────────────
  echo ""
  echo -e "${BOLD}════════════════════════════════════════════════════${RESET}"

  if config_is_filled; then
    # Identify which config file was found for the status message
    local _found_conf="$CONFIG_FILE_SYSTEM"
    [[ ! -f "$CONFIG_FILE_SYSTEM" ]] && _found_conf="${HOME}/.dispatch.conf"
    local _host
    _host=$(grep -E '^SMTP_HOST=' "$_found_conf" 2>/dev/null | cut -d= -f2- | tr -d '"' | tr -d "'" | xargs)
    echo ""
    success "Existing SMTP config detected — skipping setup"
    info   "  Config : $_found_conf"
    info   "  Host   : $_host"
    info   "  Edit that file to change settings at any time."
    echo ""
    # Read SMTP_ENABLED from existing config so the summary line is accurate
    SMTP_ENABLED_CFG=$(grep -E '^SMTP_ENABLED=' "$_found_conf" 2>/dev/null | cut -d= -f2- | tr -d '"' | tr -d "'" | xargs || echo "false")
    SMTP_TO_CFG=$(grep -E '^SMTP_TO=' "$_found_conf" 2>/dev/null | cut -d= -f2- | tr -d '"' | tr -d "'" | xargs || echo "")
  else
    configure_smtp

    # ── Write config ───────────────────────────────────────────────────────────
    echo -e "${BOLD}  Writing configuration...${RESET}"
    divider
    write_config
  fi

  # ── PATH check ───────────────────────────────────────────────────────────────
  echo ""
  local resolved
  resolved=$(command -v rsync 2>/dev/null || echo "not found")
  if [[ "$resolved" == "$WRAPPER_DST" ]]; then
    success "PATH check: rsync → $WRAPPER_DST ✔"
  else
    warn "PATH check: rsync resolves to '$resolved' instead of '$WRAPPER_DST'"
    warn "Ensure $INSTALL_DIR comes before $(dirname "$resolved") in \$PATH"
    warn "Add to /etc/environment:  PATH=\"${INSTALL_DIR}:\$PATH\""
  fi

  # ── Summary ──────────────────────────────────────────────────────────────────
  echo ""
  echo -e "${BOLD}${GREEN}╔════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${GREEN}║           Installation Complete! ✔                ║${RESET}"
  echo -e "${BOLD}${GREEN}╚════════════════════════════════════════════════════╝${RESET}"
  echo ""
  info "Wrapper    : $WRAPPER_DST"
  info "Config     : $CONFIG_FILE_SYSTEM"
  info "Logs       : $LOG_DIR"
  info "Real rsync : $REAL_RSYNC"
  info "SMTP       : $( [[ "$SMTP_ENABLED_CFG" == "true" ]] && echo "enabled → ${SMTP_TO_CFG}" || echo "disabled" )"
  echo ""
  echo -e "  ${BOLD}Quick test:${RESET}"
  echo "    rsync --version"
  if [[ "$SMTP_ENABLED_CFG" == "true" ]]; then
    echo "    rsync --smtp-enable --logfile -avhn /tmp/ /tmp/rsync-test-out/"
  else
    echo "    rsync --smtp-enable --logfile -avhn /tmp/ /tmp/rsync-test-out/"
    echo "    (add --smtp-enable to test notifications when you're ready)"
  fi
  echo ""
}

# =============================================================================
# UNINSTALL
# =============================================================================
do_uninstall() {
  banner "Uninstaller"
  check_root

  echo ""
  warn "This will remove Dispatch and restore native rsync behaviour."
  echo ""

  if ! prompt_yn "Continue with uninstall?" "n"; then
    info "Uninstall cancelled."
    exit 0
  fi

  echo ""
  local removed=0

  if [[ -f "$WRAPPER_DST" ]]; then
    if grep -q 'Dispatch' "$WRAPPER_DST" 2>/dev/null; then
      rm -f "$WRAPPER_DST"
      success "Removed wrapper: $WRAPPER_DST"
      (( removed++ )) || true
    else
      warn "$WRAPPER_DST exists but is not Dispatch — leaving it untouched."
    fi
  else
    info "Wrapper not found at $WRAPPER_DST"
  fi

  # Restore backup if present
  local backup="${WRAPPER_DST}${BACKUP_SUFFIX}"
  if [[ -f "$backup" ]]; then
    mv "$backup" "$WRAPPER_DST"
    success "Restored backup: $WRAPPER_DST"
  fi

  # Config file
  if [[ -f "$CONFIG_FILE_SYSTEM" ]]; then
    echo ""
    if prompt_yn "Remove config file ${CONFIG_FILE_SYSTEM}?" "n"; then
      rm -f "$CONFIG_FILE_SYSTEM"
      success "Removed: $CONFIG_FILE_SYSTEM"
    else
      info "Keeping: $CONFIG_FILE_SYSTEM"
    fi
  fi

  # Log directory
  if [[ -d "$LOG_DIR" ]]; then
    echo ""
    if prompt_yn "Remove log directory ${LOG_DIR}?" "n"; then
      rm -rf "$LOG_DIR"
      success "Removed: $LOG_DIR"
    else
      info "Keeping: $LOG_DIR"
    fi
  fi

  # Lock directory
  [[ -d "$LOCK_DIR" ]] && { rm -rf "$LOCK_DIR"; success "Removed lock dir: $LOCK_DIR"; }

  echo ""
  [[ $removed -gt 0 ]] && success "Dispatch removed. Native rsync restored." || info "Nothing removed."
  echo ""
}

# =============================================================================
# UPDATE
# =============================================================================
do_update() {
  banner "Updater"
  check_root

  local current="unknown"
  if [[ -f "$WRAPPER_DST" ]]; then
    current=$(grep -oE 'readonly VERSION="[^"]+"' "$WRAPPER_DST" 2>/dev/null | sed 's/readonly VERSION="//;s/"//' || echo "unknown")
    [[ -z "$current" ]] && current="unknown"
    info "Installed : v${current}"
    info "Available : v${WRAPPER_VERSION}"
    echo ""
  else
    warn "Dispatch not installed. Running full install."
    do_install
    return
  fi

  if [[ "$current" == "$WRAPPER_VERSION" ]]; then
    success "Already up to date (v${WRAPPER_VERSION})."
    exit 0
  fi

  # Show whether existing config will be preserved
  if config_is_filled; then
    local _found_conf="$CONFIG_FILE_SYSTEM"
    [[ ! -f "$CONFIG_FILE_SYSTEM" ]] && _found_conf="${HOME}/.dispatch.conf"
    info "Existing SMTP config found at: $_found_conf"
    info "It will be preserved — SMTP setup will be skipped."
  else
    info "No existing SMTP config detected — you will be prompted to configure it."
  fi
  echo ""

  if prompt_yn "Update v${current} → v${WRAPPER_VERSION}?" "y"; then
    backup_existing
    do_install
    success "Updated: v${current} → v${WRAPPER_VERSION}"
  else
    info "Update cancelled."
  fi
}

# =============================================================================
# HELP
# =============================================================================
usage() {
  cat <<EOF

${BOLD}Dispatch installer${RESET} v${WRAPPER_VERSION}

${BOLD}Usage:${RESET}
  sudo bash install.sh               Interactive install
  sudo bash install.sh --uninstall   Remove Dispatch
  sudo bash install.sh --update      Update to latest version
  sudo bash install.sh --help        Show this help

${BOLD}One-liners:${RESET}
  # The -s flag is required when piping — it tells bash to read from stdin
  # so that subsequent arguments are passed to the script, not to bash itself
  curl -fsSL https://raw.githubusercontent.com/SaeedHurzuk/Dispatch/refs/heads/main/install.sh | sudo bash -s
  curl -fsSL https://raw.githubusercontent.com/SaeedHurzuk/Dispatch/refs/heads/main/install.sh | sudo bash -s -- --update
  curl -fsSL https://raw.githubusercontent.com/SaeedHurzuk/Dispatch/refs/heads/main/install.sh | sudo bash -s -- --uninstall

EOF
  exit 0
}

# =============================================================================
# ENTRY POINT
# =============================================================================
case "${1:-}" in
  --uninstall) do_uninstall ;;
  --update)    do_update    ;;
  --help|-h)   usage        ;;
  "")          do_install   ;;
  *)           die "Unknown argument: '$1'. Run: sudo bash install.sh --help" ;;
esac
