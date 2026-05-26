#!/usr/bin/env bash

set -uo pipefail

AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"
AGENT_PORT="${AGENT_PORT:-15034}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
AGENT_PROCESS_PATTERN="${AGENT_PROCESS_PATTERN:-agent-app|agent_app.py}"

LOG_FILE="${AGENT_LOG_DIR}/monitor.log"
MAX_LOG_BYTES="${MAX_LOG_BYTES:-10485760}"
KEEP_ROTATED="${KEEP_ROTATED:-9}"
CPU_THRESHOLD="${CPU_THRESHOLD:-20}"
MEM_THRESHOLD="${MEM_THRESHOLD:-10}"
DISK_THRESHOLD="${DISK_THRESHOLD:-80}"

umask 007

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
    CYAN="$(tput setaf 6)"
    RESET="$(tput sgr0)"
  else
    BOLD=""
    DIM=""
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    CYAN=""
    RESET=""
  fi
}

print_line() {
  printf '%s\n' "$*"
}

rule() {
  printf '%s%s%s\n' "$DIM" "------------------------------------------------------------" "$RESET"
}

title() {
  printf '\n%s%s%s\n' "${BOLD}${BLUE}" "$1" "$RESET"
  rule
}

section() {
  printf '\n%s%s%s\n' "${BOLD}${CYAN}" "$1" "$RESET"
}

status_line() {
  local label="$1"
  local status="$2"
  local detail="${3:-}"
  local color="$GREEN"

  case "$status" in
    OK) color="$GREEN" ;;
    WARN | WARNING) color="$YELLOW" ;;
    ERROR | FAIL) color="$RED" ;;
  esac

  if [ -n "$detail" ]; then
    printf '  %-38s %s[%s]%s %s\n' "$label" "$color" "$status" "$RESET" "$detail"
  else
    printf '  %-38s %s[%s]%s\n' "$label" "$color" "$status" "$RESET"
  fi
}

metric_line() {
  printf '  %-14s %s%8s%s\n' "$1" "$CYAN" "$2" "$RESET"
}

info_line() {
  printf '%s[INFO]%s %s\n' "$BLUE" "$RESET" "$1"
}

warn_line() {
  printf '%s[WARNING]%s %s\n' "$YELLOW" "$RESET" "$1"
}

error_line() {
  printf '%s[ERROR]%s %s\n' "$RED" "$RESET" "$1"
}

float_gt() {
  awk -v a="$1" -v b="$2" 'BEGIN { exit !(a > b) }'
}

ensure_log_dir() {
  if ! mkdir -p "$AGENT_LOG_DIR" 2>/dev/null; then
    error_line "Cannot create log directory: ${AGENT_LOG_DIR}"
    exit 1
  fi

  if [ ! -w "$AGENT_LOG_DIR" ]; then
    error_line "Log directory is not writable: ${AGENT_LOG_DIR}"
    exit 1
  fi
}

rotate_log_if_needed() {
  [ -f "$LOG_FILE" ] || return 0

  local size rotated
  size="$(wc -c < "$LOG_FILE" 2>/dev/null || printf '0')"
  if [ "$size" -lt "$MAX_LOG_BYTES" ]; then
    return 0
  fi

  rotated="${LOG_FILE}.$(date '+%Y%m%d%H%M%S').log"
  if mv "$LOG_FILE" "$rotated"; then
    : > "$LOG_FILE"
    chmod 0660 "$LOG_FILE" 2>/dev/null || true
    ls -1t "${LOG_FILE}".*.log 2>/dev/null | awk -v keep="$KEEP_ROTATED" 'NR > keep' | xargs -r rm -f
  else
    warn_line "Log rotation failed for ${LOG_FILE}"
  fi
}

find_agent_pid() {
  ps -eo pid=,comm=,args= | awk \
    -v me="$$" \
    -v parent="$PPID" \
    -v pattern="$AGENT_PROCESS_PATTERN" '
      $1 == me || $1 == parent { next }
      $2 ~ /^(awk|bash|cron|grep|monitor\.sh|ps|runuser|sh|sudo|tail)$/ { next }
      $0 ~ /monitor\.sh/ { next }
      $2 ~ /^agent-app/ || $0 ~ /agent_app\.py/ || $0 ~ pattern {
        print $1
        exit
      }
    '
}

is_port_listening() {
  ss -H -ltn 2>/dev/null | awk -v port="$AGENT_PORT" '
    {
      n = split($4, parts, ":")
      if (parts[n] == port) {
        found = 1
      }
    }
    END { exit found ? 0 : 1 }
  '
}

firewall_status() {
  if command -v ufw >/dev/null 2>&1; then
    if ufw status 2>/dev/null | grep -q '^Status: active'; then
      status_line "Firewall UFW" "OK" "active"
      return 0
    fi

    if [ -r /etc/ufw/ufw.conf ] && grep -q '^ENABLED=yes' /etc/ufw/ufw.conf; then
      status_line "Firewall UFW" "OK" "active"
      return 0
    fi
  fi

  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state 2>/dev/null | grep -q '^running$'; then
    status_line "Firewall firewalld" "OK" "running"
    return 0
  fi

  warn_line "Firewall is not active or status is unavailable"
  return 0
}

read_cpu_snapshot() {
  awk '/^cpu / {
    idle = $5 + $6
    total = 0
    for (i = 2; i <= NF; i++) {
      total += $i
    }
    print total, idle
  }' /proc/stat
}

cpu_usage() {
  local total1 idle1 total2 idle2 total_delta idle_delta
  read -r total1 idle1 < <(read_cpu_snapshot)
  sleep 1
  read -r total2 idle2 < <(read_cpu_snapshot)

  total_delta=$((total2 - total1))
  idle_delta=$((idle2 - idle1))

  awk -v total="$total_delta" -v idle="$idle_delta" 'BEGIN {
    if (total <= 0) {
      printf "0.0"
    } else {
      printf "%.1f", (100 * (total - idle) / total)
    }
  }'
}

mem_usage() {
  awk '
    /^MemTotal:/ { total = $2 }
    /^MemAvailable:/ { available = $2 }
    END {
      if (total <= 0) {
        printf "0.0"
      } else {
        printf "%.1f", ((total - available) * 100 / total)
      }
    }
  ' /proc/meminfo
}

disk_usage() {
  df -P / | awk 'NR == 2 { gsub("%", "", $5); print $5 }'
}

main() {
  setup_style
  ensure_log_dir

  title "SYSTEM MONITOR RESULT"
  section "HEALTH CHECK"

  local pid cpu mem disk timestamp
  pid="$(find_agent_pid)"
  if [ -z "$pid" ]; then
    status_line "Process ${AGENT_PROCESS_PATTERN}" "ERROR"
    exit 1
  fi
  status_line "Process ${AGENT_PROCESS_PATTERN}" "OK" "PID ${pid}"

  if ! is_port_listening; then
    status_line "TCP port ${AGENT_PORT}" "ERROR"
    exit 1
  fi
  status_line "TCP port ${AGENT_PORT}" "OK" "LISTEN"

  firewall_status

  cpu="$(cpu_usage)"
  mem="$(mem_usage)"
  disk="$(disk_usage)"

  section "RESOURCE MONITORING"
  metric_line "CPU Usage" "${cpu}%"
  metric_line "MEM Usage" "${mem}%"
  metric_line "DISK Used" "${disk}%"
  print_line ""

  if float_gt "$cpu" "$CPU_THRESHOLD"; then
    warn_line "CPU threshold exceeded (${cpu}% > ${CPU_THRESHOLD}%)"
  fi

  if float_gt "$mem" "$MEM_THRESHOLD"; then
    warn_line "MEM threshold exceeded (${mem}% > ${MEM_THRESHOLD}%)"
  fi

  if float_gt "$disk" "$DISK_THRESHOLD"; then
    warn_line "DISK threshold exceeded (${disk}% > ${DISK_THRESHOLD}%)"
  fi

  rotate_log_if_needed
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  printf '[%s] PID:%s CPU:%s%% MEM:%s%% DISK_USED:%s%%\n' "$timestamp" "$pid" "$cpu" "$mem" "$disk" >> "$LOG_FILE"
  chmod 0660 "$LOG_FILE" 2>/dev/null || true

  print_line ""
  info_line "Log appended: ${LOG_FILE}"
}

main "$@"
