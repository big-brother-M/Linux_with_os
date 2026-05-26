#!/usr/bin/env bash

set -uo pipefail

CONTAINER="${CONTAINER:-agent-lab}"

if [ -t 1 ] \
  && [ -z "${NO_COLOR:-}" ] \
  && [ "${TERM:-dumb}" != "dumb" ] \
  && command -v tput >/dev/null 2>&1 \
  && [ "$(tput colors 2>/dev/null || printf '0')" -ge 8 ]; then
  bold="$(tput bold)"
  dim="$(tput dim 2>/dev/null || true)"
  red="$(tput setaf 1)"
  green="$(tput setaf 2)"
  yellow="$(tput setaf 3)"
  blue="$(tput setaf 4)"
  reset="$(tput sgr0)"
else
  bold=""
  dim=""
  red=""
  green=""
  yellow=""
  blue=""
  reset=""
fi

line() {
  printf '%s\n' "${dim}────────────────────────────────────────────────────────────${reset}"
}

section() {
  printf '\n%s%s%s\n' "$bold$blue" "$1" "$reset"
  line
}

ok() {
  printf '%s[OK]%s %s\n' "$green" "$reset" "$1"
}

warn() {
  printf '%s[WARN]%s %s\n' "$yellow" "$reset" "$1"
}

fail() {
  printf '%s[FAIL]%s %s\n' "$red" "$reset" "$1"
}

run_in_container() {
  docker exec "$CONTAINER" bash -lc "$1" 2>/dev/null
}

container_running() {
  [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" = "true" ]
}

check_contains() {
  local label="$1"
  local command="$2"
  local pattern="$3"
  local output

  output="$(run_in_container "$command" || true)"
  if printf '%s\n' "$output" | grep -Eq "$pattern"; then
    ok "$label"
  else
    fail "$label"
  fi
  printf '%s\n' "$output" | sed 's/^/  /'
}

check_all_contains() {
  local label="$1"
  local command="$2"
  local output pattern missing
  shift 2

  output="$(run_in_container "$command" || true)"
  missing=0

  for pattern in "$@"; do
    if ! printf '%s\n' "$output" | grep -Eq "$pattern"; then
      missing=1
      printf '  missing pattern: %s\n' "$pattern"
    fi
  done

  if [ "$missing" -eq 0 ]; then
    ok "$label"
  else
    fail "$label"
  fi

  printf '%s\n' "$output" | sed 's/^/  /'
}

check_no_extra_ufw_rules() {
  local output unexpected

  output="$(run_in_container "ufw status verbose" || true)"
  unexpected="$(printf '%s\n' "$output" | awk '
    /ALLOW IN/ && $0 !~ /^[[:space:]]*(20022|15034)\/tcp([[:space:]]+\(v6\))?[[:space:]]+ALLOW IN/ {
      print
    }
  ')"

  if [ -z "$unexpected" ]; then
    ok "no extra UFW ingress allow rules"
  else
    fail "unexpected UFW ingress allow rules"
    printf '%s\n' "$unexpected" | sed 's/^/  /'
  fi
}

main() {
  clear 2>/dev/null || true
  printf '%sAgent Lab Status%s\n' "$bold" "$reset"
  printf 'Container: %s\n' "$CONTAINER"
  printf 'Time: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"

  section "Docker"
  if container_running; then
    ok "container is running"
  else
    fail "container is not running"
    docker compose ps -a 2>/dev/null || true
    exit 1
  fi
  docker compose ps "$CONTAINER" 2>/dev/null || docker ps --filter "name=${CONTAINER}"

  section "Boot"
  check_all_contains "boot sequence completed" \
    "grep -E '\\[OK\\]|Agent READY' /var/log/agent-app/agent-app.console.log" \
    '\[1/5\].*\[OK\]' \
    '\[2/5\].*\[OK\]' \
    '\[3/5\].*\[OK\]' \
    '\[4/5\].*\[OK\]' \
    '\[5/5\].*\[OK\]' \
    'Agent READY'

  section "Ports"
  check_all_contains "SSH 20022 and APP 15034 are listening" \
    "ss -tulnp | grep -E ':20022|:15034'" \
    ':20022[[:space:]]' \
    ':15034[[:space:]]'

  section "Firewall"
  check_all_contains "UFW is active and only required ingress ports are allowed" \
    "ufw status verbose" \
    '^Status: active$' \
    '^Default: deny \(incoming\), allow \(outgoing\)' \
    '^20022/tcp[[:space:]]+ALLOW IN' \
    '^15034/tcp[[:space:]]+ALLOW IN'
  check_no_extra_ufw_rules

  section "Accounts"
  run_in_container "id agent-admin; id agent-dev; id agent-test" | sed 's/^/  /'

  section "Permissions"
  run_in_container "ls -ld /home/agent-admin/agent-app /home/agent-admin/agent-app/upload_files /home/agent-admin/agent-app/api_keys /var/log/agent-app /home/agent-admin/agent-app/bin/monitor.sh" | sed 's/^/  /'

  section "Monitor"
  if run_in_container "sudo -u agent-admin /home/agent-admin/agent-app/bin/monitor.sh >/tmp/lab_status_monitor.out 2>&1"; then
    ok "monitor.sh executed"
  else
    fail "monitor.sh failed"
  fi
  run_in_container "cat /tmp/lab_status_monitor.out; echo; echo 'Recent monitor.log:'; tail -n 5 /var/log/agent-app/monitor.log" | sed 's/^/  /'

  section "Cron"
  run_in_container "crontab -u agent-admin -l; echo; echo 'monitor.log line count:'; wc -l /var/log/agent-app/monitor.log" | sed 's/^/  /'

  section "Report"
  run_in_container "sudo -u agent-admin /home/agent-admin/agent-app/bin/report.sh | tail -n 20" | sed 's/^/  /'

  printf '\n%sTip%s: live view -> %swhile true; do ./bin/lab_status.sh; sleep 5; done%s\n' "$bold" "$reset" "$bold" "$reset"
  printf '%sTip%s: follow app logs -> %sdocker logs -f agent-lab%s\n' "$bold" "$reset" "$bold" "$reset"
}

main "$@"
