#!/usr/bin/env bash

set -uo pipefail

AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"
AGENT_PORT="${AGENT_PORT:-15034}"
AGENT_UPLOAD_DIR="${AGENT_UPLOAD_DIR:-${AGENT_HOME}/upload_files}"
AGENT_KEY_PATH="${AGENT_KEY_PATH:-${AGENT_HOME}/api_keys/t_secret.key}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
AGENT_PROCESS_PATTERN="${AGENT_PROCESS_PATTERN:-agent-app|agent_app.py}"
APP_CONSOLE_LOG="${AGENT_LOG_DIR}/agent-app.console.log"

export AGENT_HOME AGENT_PORT AGENT_UPLOAD_DIR AGENT_KEY_PATH AGENT_LOG_DIR AGENT_PROCESS_PATTERN

log() {
  printf '[entrypoint] %s\n' "$*"
}

configure_firewall() {
  if ! command -v ufw >/dev/null 2>&1; then
    log "UFW is not installed"
    return 0
  fi

  log "Configuring UFW: allow tcp/20022 and tcp/${AGENT_PORT}"
  ufw --force reset >/dev/null 2>&1 || true
  ufw default deny incoming >/dev/null 2>&1 || true
  ufw default allow outgoing >/dev/null 2>&1 || true
  ufw allow 20022/tcp >/dev/null 2>&1 || true
  ufw allow "${AGENT_PORT}/tcp" >/dev/null 2>&1 || true

  if ufw --force enable >/dev/null 2>&1; then
    log "UFW enabled"
  else
    log "WARNING: UFW enable failed. Docker must run with NET_ADMIN capability."
  fi
}

start_sshd() {
  mkdir -p /run/sshd
  ssh-keygen -A >/dev/null 2>&1 || true
  /usr/sbin/sshd -f /etc/ssh/sshd_config
  log "sshd listening on port 20022"
}

start_cron() {
  /usr/sbin/cron
  log "cron started for agent-admin monitor schedule"
}

prepare_logs() {
  mkdir -p "$AGENT_LOG_DIR"
  touch "$APP_CONSOLE_LOG" "${AGENT_LOG_DIR}/monitor.cron.log" "${AGENT_LOG_DIR}/archive.cron.log"
  chown agent-admin:agent-core "$APP_CONSOLE_LOG" "${AGENT_LOG_DIR}/monitor.cron.log" "${AGENT_LOG_DIR}/archive.cron.log"
  chmod 0660 "$APP_CONSOLE_LOG" "${AGENT_LOG_DIR}/monitor.cron.log" "${AGENT_LOG_DIR}/archive.cron.log"
}

start_agent_app() {
  log "starting agent app as agent-admin"
  runuser -u agent-admin -- env \
    AGENT_HOME="$AGENT_HOME" \
    AGENT_PORT="$AGENT_PORT" \
    AGENT_UPLOAD_DIR="$AGENT_UPLOAD_DIR" \
    AGENT_KEY_PATH="$AGENT_KEY_PATH" \
    AGENT_LOG_DIR="$AGENT_LOG_DIR" \
    AGENT_PROCESS_PATTERN="$AGENT_PROCESS_PATTERN" \
    bash -c 'cd "$AGENT_HOME" && exec "$AGENT_HOME/agent-app"' \
    >> "$APP_CONSOLE_LOG" 2>&1 &
  APP_PID=$!
  log "agent app pid: ${APP_PID}"
}

shutdown() {
  log "shutting down"
  if [ "${APP_PID:-}" ]; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  pkill cron 2>/dev/null || true
  pkill sshd 2>/dev/null || true
  exit 0
}

main() {
  trap shutdown INT TERM

  configure_firewall
  start_sshd
  start_cron
  prepare_logs
  start_agent_app

  tail -F "$APP_CONSOLE_LOG" "${AGENT_LOG_DIR}/monitor.cron.log" "${AGENT_LOG_DIR}/archive.cron.log" &
  TAIL_PID=$!

  wait "$APP_PID"
  status=$?
  kill "$TAIL_PID" 2>/dev/null || true
  log "agent app exited with status ${status}"
  exit "$status"
}

main "$@"
