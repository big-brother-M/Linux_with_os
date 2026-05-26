#!/usr/bin/env bash

set -uo pipefail

AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
ARCHIVE_DIR="${ARCHIVE_DIR:-/var/log/monitor/agent-app/archive}"
COMPRESS_AFTER_DAYS="${COMPRESS_AFTER_DAYS:-7}"
DELETE_AFTER_DAYS="${DELETE_AFTER_DAYS:-30}"

setup_style() {
  if [ -t 1 ] \
    && [ -z "${NO_COLOR:-}" ] \
    && [ "${TERM:-dumb}" != "dumb" ] \
    && command -v tput >/dev/null 2>&1 \
    && [ "$(tput colors 2>/dev/null || printf '0')" -ge 8 ]; then
    BOLD="$(tput bold)"
    DIM="$(tput dim 2>/dev/null || true)"
    RED="$(tput setaf 1)"
    GREEN="$(tput setaf 2)"
    YELLOW="$(tput setaf 3)"
    BLUE="$(tput setaf 4)"
    RESET="$(tput sgr0)"
  else
    BOLD=""
    DIM=""
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    RESET=""
  fi
}

title() {
  printf '\n%s%s%s\n' "${BOLD}${BLUE}" "$1" "$RESET"
  printf '%s%s%s\n' "$DIM" "------------------------------------------------------------" "$RESET"
}

info() {
  printf '%s[INFO]%s %s\n' "$BLUE" "$RESET" "$1"
}

ok() {
  printf '%s[OK]%s %s\n' "$GREEN" "$RESET" "$1"
}

warn() {
  printf '%s[WARNING]%s %s\n' "$YELLOW" "$RESET" "$1"
}

mkdir_if_possible() {
  if ! mkdir -p "$ARCHIVE_DIR" 2>/dev/null; then
    warn "Archive directory cannot be created: ${ARCHIVE_DIR}"
    exit 0
  fi
}

compress_old_logs() {
  local found compressed file base dest tmp
  found=0
  compressed=0

  while IFS= read -r file; do
    found=1
    base="$(basename "$file")"
    dest="${ARCHIVE_DIR}/${base}.$(date '+%Y%m%d%H%M%S').gz"
    tmp="${dest}.tmp"

    if gzip -c "$file" > "$tmp" && mv "$tmp" "$dest" && rm -f "$file"; then
      compressed=$((compressed + 1))
      ok "Archived: ${file} -> ${dest}"
    else
      rm -f "$tmp"
      warn "Failed to archive: ${file}"
    fi
  done < <(find "$AGENT_LOG_DIR" -maxdepth 1 -type f -name '*.log' -mtime +"$((COMPRESS_AFTER_DAYS - 1))" 2>/dev/null)

  if [ "$found" -eq 0 ]; then
    info "No log files older than ${COMPRESS_AFTER_DAYS} days found in ${AGENT_LOG_DIR}"
  else
    info "Archived ${compressed} file(s)"
  fi
}

delete_expired_archives() {
  local deleted file
  deleted=0

  while IFS= read -r file; do
    if rm -f "$file"; then
      deleted=$((deleted + 1))
      ok "Deleted expired archive: ${file}"
    else
      warn "Failed to delete expired archive: ${file}"
    fi
  done < <(find "$ARCHIVE_DIR" -maxdepth 1 -type f -name '*.gz' -mtime +"$((DELETE_AFTER_DAYS - 1))" 2>/dev/null)

  if [ "$deleted" -eq 0 ]; then
    info "No archives older than ${DELETE_AFTER_DAYS} days found in ${ARCHIVE_DIR}"
  fi
}

main() {
  setup_style
  title "LOG ARCHIVE MAINTENANCE"

  if [ ! -d "$AGENT_LOG_DIR" ]; then
    warn "Log directory does not exist: ${AGENT_LOG_DIR}"
    exit 0
  fi

  if [ ! -r "$AGENT_LOG_DIR" ]; then
    warn "Log directory is not readable: ${AGENT_LOG_DIR}"
    exit 0
  fi

  mkdir_if_possible

  if [ ! -w "$ARCHIVE_DIR" ]; then
    warn "Archive directory is not writable: ${ARCHIVE_DIR}"
    exit 0
  fi

  compress_old_logs
  delete_expired_archives
}

main "$@"
