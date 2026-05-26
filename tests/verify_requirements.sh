#!/usr/bin/env bash

set -u

failures=0

fail() {
  printf '[FAIL] %s\n' "$1" >&2
  failures=$((failures + 1))
}

pass() {
  printf '[PASS] %s\n' "$1"
}

assert_contains() {
  local file="$1"
  local needle="$2"
  local label="$3"

  if grep -Fq "$needle" "$file"; then
    pass "$label"
  else
    fail "$label"
    printf '       expected %s to contain: %s\n' "$file" "$needle" >&2
  fi
}

assert_not_contains() {
  local file="$1"
  local needle="$2"
  local label="$3"

  if grep -Fq "$needle" "$file"; then
    fail "$label"
    printf '       unexpected %s content: %s\n' "$file" "$needle" >&2
  else
    pass "$label"
  fi
}

assert_not_line() {
  local file="$1"
  local line="$2"
  local label="$3"

  if grep -Fxq "$line" "$file"; then
    fail "$label"
    printf '       unexpected exact line in %s: %s\n' "$file" "$line" >&2
  else
    pass "$label"
  fi
}

assert_line() {
  local file="$1"
  local line="$2"
  local label="$3"

  if grep -Fxq "$line" "$file"; then
    pass "$label"
  else
    fail "$label"
    printf '       expected exact line in %s: %s\n' "$file" "$line" >&2
  fi
}

assert_line Dockerfile \
  "    AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys \\" \
  "Docker image exports AGENT_KEY_PATH as the provided app expects"

assert_line docker-compose.yml \
  "      AGENT_KEY_PATH: /home/agent-admin/agent-app/api_keys" \
  "Compose runtime passes AGENT_KEY_PATH as the provided app expects"

assert_contains submission-report.md \
  '제공 앱은 `AGENT_KEY_PATH`를 키 디렉토리로 검증한다' \
  "Submission report documents the provided app AGENT_KEY_PATH compatibility requirement"

assert_contains Dockerfile \
  "\${AGENT_KEY_PATH}/t_secret.key" \
  "Docker image creates the project-required t_secret.key file"

assert_contains Dockerfile \
  "\${AGENT_KEY_PATH}/secret.key" \
  "Docker image creates the provided-app-required secret.key file"

assert_contains submission-report.md \
  "api_keys/secret.key" \
  "Submission report documents the app-compatible secret.key file"

assert_contains submission-report.md \
  "프로세스 식별은 \`ps -eo pid=,comm=,args=\`와 \`awk\`를 사용한다" \
  "Submission report explains process identification choice"

assert_contains submission-report.md \
  "CPU는 \`/proc/stat\`의 전체 CPU tick을 1초 간격으로 두 번 읽고" \
  "Submission report explains CPU parsing"

assert_contains submission-report.md \
  "Root 원격 접속 차단은 단일 최고권한 계정 탈취 위험을 낮추며" \
  "Submission report explains root login security rationale"

assert_contains submission-report.md \
  "리다이렉션 \`>\`는 파일을 새로 덮어쓰고, \`>>\`는 파일 끝에 추가한다" \
  "Submission report explains redirection behavior"

assert_contains bin/lab_status.sh \
  "check_all_contains \"SSH 20022 and APP 15034 are listening\"" \
  "Status helper verifies SSH and APP listeners independently"

assert_contains bin/lab_status.sh \
  "check_all_contains \"UFW is active and only required ingress ports are allowed\"" \
  "Status helper verifies UFW active state and required allow rules independently"

if [ "$failures" -gt 0 ]; then
  printf '\n%d requirement check(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\nAll requirement checks passed.\n'
