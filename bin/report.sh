#!/usr/bin/env bash

set -uo pipefail

AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
LOG_FILE="${1:-${AGENT_LOG_DIR}/monitor.log}"
START_TIME="${2:-}"
END_TIME="${3:-}"

setup_style() {
  if [ -t 1 ] \
    && [ -z "${NO_COLOR:-}" ] \
    && [ "${TERM:-dumb}" != "dumb" ] \
    && command -v tput >/dev/null 2>&1 \
    && [ "$(tput colors 2>/dev/null || printf '0')" -ge 8 ]; then
    BOLD="$(tput bold)"
    DIM="$(tput dim 2>/dev/null || true)"
    RED="$(tput setaf 1)"
    BLUE="$(tput setaf 4)"
    CYAN="$(tput setaf 6)"
    RESET="$(tput sgr0)"
  else
    BOLD=""
    DIM=""
    RED=""
    BLUE=""
    CYAN=""
    RESET=""
  fi
}

usage() {
  cat <<'EOF'
Usage:
  report.sh [log_file] [start_time] [end_time]

Examples:
  report.sh
  report.sh /var/log/agent-app/monitor.log "2026-02-25 13:00:00" "2026-02-25 14:00:00"
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ ! -r "$LOG_FILE" ]; then
  setup_style
  printf '%s[ERROR]%s Cannot read log file: %s\n' "$RED" "$RESET" "$LOG_FILE" >&2
  exit 1
fi

setup_style

awk \
  -v start="$START_TIME" \
  -v end="$END_TIME" \
  -v bold="$BOLD" \
  -v dim="$DIM" \
  -v blue="$BLUE" \
  -v cyan="$CYAN" \
  -v reset="$RESET" '
  function capture_metric(prefix, value, i, raw) {
    value = ""
    for (i = 1; i <= NF; i++) {
      if ($i ~ ("^" prefix ":")) {
        raw = $i
        sub(("^" prefix ":"), "", raw)
        sub("%$", "", raw)
        value = raw + 0
      }
    }
    return value
  }

  function update_stats(name, value, ts) {
    sum[name] += value
    if (!(name in seen) || value > max[name]) {
      max[name] = value
      max_ts[name] = ts
    }
    if (!(name in seen) || value < min[name]) {
      min[name] = value
      min_ts[name] = ts
    }
    seen[name] = 1
  }

  /^\[/ {
    ts = substr($0, 2, 19)
    if (ts !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]$/) {
      next
    }
    if (start != "" && ts < start) {
      next
    }
    if (end != "" && ts > end) {
      next
    }

    cpu = capture_metric("CPU")
    mem = capture_metric("MEM")
    disk = capture_metric("DISK_USED")
    update_stats("CPU", cpu, ts)
    update_stats("Memory", mem, ts)
    update_stats("Disk", disk, ts)
    count++
  }

  END {
    printf "\n%s%s%s\n", bold blue, "STATISTICS REPORT", reset
    printf "%s%s%s\n", dim, "------------------------------------------------------------", reset

    if (count == 0) {
      printf "%-10s %10s\n", "Samples", "0"
      exit 0
    }

    printf "%-10s %10s %26s %26s\n", "Metric", "Average", "Maximum", "Minimum"
    printf "%s%s%s\n", dim, "------------------------------------------------------------", reset
    split("CPU Memory Disk", names, " ")
    for (i = 1; i <= 3; i++) {
      name = names[i]
      printf "%s%-10s%s %9.1f%% %9.1f%% at %-16s %9.1f%% at %-16s\n",
        cyan, name, reset,
        sum[name] / count,
        max[name], max_ts[name],
        min[name], min_ts[name]
    }

    printf "%s%s%s\n", dim, "------------------------------------------------------------", reset
    printf "%-10s %10d samples\n", "Samples", count
  }
' "$LOG_FILE"
