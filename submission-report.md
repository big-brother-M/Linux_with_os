# 시스템 관제 자동화 스크립트 개발 수행 내역서

## 1. 실행 환경

- 목표 환경: Docker 컨테이너 내부 Ubuntu 22.04 LTS
- 컨테이너 이름: `agent-lab`
- SSH 포트: `20022/tcp`
- 앱 포트: `15034/tcp`
- 방화벽: UFW
- 기본 계정 비밀번호: `agentpass` (로컬 Docker 실습 전용)
- `AGENT_HOME`: `/home/agent-admin/agent-app`
- `AGENT_LOG_DIR`: `/var/log/agent-app`

실행:

```bash
docker compose up --build
docker exec -it agent-lab bash
```

## 2. 설정/명령어 기록

### SSH 설정

```bash
grep -R "Port 20022\|PermitRootLogin no" /etc/ssh/sshd_config /etc/ssh/sshd_config.d
ss -tulnp | grep ':20022'
```

적용 내용:

- `/etc/ssh/sshd_config.d/agent-lab.conf`
- `Port 20022`
- `PermitRootLogin no`
- `PasswordAuthentication yes`

### 방화벽 설정

```bash
ufw status verbose
```

적용 내용:

- UFW 활성화
- inbound 기본 deny
- outbound 기본 allow
- `20022/tcp` 허용
- `15034/tcp` 허용

Docker Desktop/macOS에서는 UFW가 호스트 방화벽을 제어하지 않고 컨테이너 내부 네트워크 정책만 다룬다.

### 계정/그룹

```bash
id agent-admin
id agent-dev
id agent-test
```

적용 내용:

- `agent-admin`: `agent-common`, `agent-core`
- `agent-dev`: `agent-common`, `agent-core`
- `agent-test`: `agent-common`

### 디렉토리/권한/ACL

```bash
ls -ld /home/agent-admin/agent-app \
  /home/agent-admin/agent-app/upload_files \
  /home/agent-admin/agent-app/api_keys \
  /var/log/agent-app

getfacl /home/agent-admin/agent-app/upload_files
getfacl /home/agent-admin/agent-app/api_keys
getfacl /var/log/agent-app
```

적용 내용:

- `upload_files`: group `agent-common`, mode `2770`, 기본 ACL `agent-common:rwx`
- `api_keys`: group `agent-core`, mode `2770`, `agent-test` 접근 불가
- `/var/log/agent-app`: group `agent-core`, mode `2770`, monitor 로그 기록 가능
- `$AGENT_HOME`: group `agent-common`, mode `2710`, 공용 디렉토리 접근에 필요한 통과 권한만 부여
- `$AGENT_HOME/bin/monitor.sh`: owner `agent-dev`, group `agent-core`, mode `750`

### 환경 변수와 키 파일

```bash
env | grep '^AGENT_'
cat /home/agent-admin/agent-app/api_keys/t_secret.key
cat /home/agent-admin/agent-app/api_keys/secret.key
```

적용 내용:

- `AGENT_HOME=/home/agent-admin/agent-app`
- `AGENT_PORT=15034`
- `AGENT_UPLOAD_DIR=/home/agent-admin/agent-app/upload_files`
- `AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys`
- `AGENT_LOG_DIR=/var/log/agent-app`
- 키 파일 경로: `/home/agent-admin/agent-app/api_keys/t_secret.key`
- 제공 앱 호환 키 파일 경로: `/home/agent-admin/agent-app/api_keys/secret.key`
- 키 파일 내용: `agent_api_key_test`

참고: `project.md`는 `AGENT_KEY_PATH` 예시를 `/home/agent-admin/agent-app/api_keys/t_secret.key`로 제시하지만, 제공 앱은 `AGENT_KEY_PATH`를 키 디렉토리로 검증한다. 실제 Boot Sequence 5단계 통과를 위해 `AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys`로 실행하고, 과제 명시 키 파일(`t_secret.key`)과 제공 앱 검증 키 파일(`secret.key`)을 동일 내용으로 함께 생성한다.

### 앱 실행 확인

```bash
grep -E "\[OK\]|Agent READY" /var/log/agent-app/agent-app.console.log
ss -tulnp | grep ':15034'
```

성공 기준:

- Boot Sequence 5단계가 모두 `[OK]`
- 마지막에 `Agent READY`
- `0.0.0.0:15034` 또는 동등 주소로 LISTEN

### monitor.sh 실행 확인

```bash
sudo -u agent-admin /home/agent-admin/agent-app/bin/monitor.sh
tail -n 5 /var/log/agent-app/monitor.log
```

로그 포맷:

```text
[YYYY-MM-DD HH:MM:SS] PID:... CPU:..% MEM:..% DISK_USED:..%
```

### cron 자동 실행 확인

```bash
crontab -u agent-admin -l
tail -n 5 /var/log/agent-app/monitor.log
sleep 70
tail -n 5 /var/log/agent-app/monitor.log
```

성공 기준:

- `agent-admin` crontab에 매분 실행 등록
- `agent-admin` crontab에 매일 03:20 `archive_logs.sh` 실행 등록
- 1분 후 `monitor.log` 라인 수 증가

## 3. 자동화 스크립트

### monitor.sh

- 위치: `/home/agent-admin/agent-app/bin/monitor.sh`
- 소유자/그룹/권한: `agent-dev:agent-core`, `750`
- Health Check:
  - `agent-app` 또는 `agent_app.py` 프로세스 확인
  - TCP `15034` LISTEN 확인
  - 실패 시 `exit 1`
- 경고:
  - UFW/firewalld 비활성 시 `[WARNING]`
  - CPU `>20%`, MEM `>10%`, DISK `>80%`
- 로그:
  - `/var/log/agent-app/monitor.log`
  - 10MB 초과 시 회전
  - active 포함 최대 10개 파일 유지

### report.sh

```bash
sudo -u agent-admin /home/agent-admin/agent-app/bin/report.sh
sudo -u agent-admin /home/agent-admin/agent-app/bin/report.sh /var/log/agent-app/monitor.log "2026-02-25 13:00:00" "2026-02-25 14:00:00"
```

기능:

- CPU/MEM/DISK 평균, 최대, 최소 출력
- 샘플 수 출력
- 선택적으로 시작/종료 시간 구간 분석

### archive_logs.sh

```bash
sudo -u agent-admin /home/agent-admin/agent-app/bin/archive_logs.sh
```

기능:

- `/var/log/agent-app/*.log` 중 7일 이상 경과 파일 gzip 압축
- `/var/log/monitor/agent-app/archive/`로 이동
- archive의 `.gz` 중 30일 이상 경과 파일 삭제
- 디렉토리 미존재, 권한 부족, 대상 파일 0개를 경고 또는 정보 메시지로 안전 처리

## 4. 필수 증거 자료 체크리스트

- [x] SSH 포트 변경 `20022` 확인
- [x] Root 원격 접속 차단 `PermitRootLogin no` 확인
- [x] UFW 활성화 확인
- [x] UFW 허용 포트가 `20022/tcp`, `15034/tcp`뿐인지 확인
- [x] `agent-admin`, `agent-dev`, `agent-test` 생성 확인
- [x] `agent-common`, `agent-core` 그룹 구성 확인
- [x] `upload_files`, `api_keys`, `/var/log/agent-app` 권한 및 ACL 확인
- [x] 앱 Boot Sequence 5단계 `[OK]` 확인
- [x] `Agent READY` 확인
- [x] TCP `15034` LISTEN 확인
- [x] `monitor.sh` 수동 실행 결과 확인
- [x] `/var/log/agent-app/monitor.log` 누적 기록 확인
- [x] `agent-admin` crontab 매분 실행 등록 확인
- [x] 1분 후 `monitor.log` 자동 증가 확인
- [x] `report.sh` 통계 리포트 출력 확인
- [x] `archive_logs.sh` 압축/아카이브/삭제 정책 확인

## 5. 점검 질문 답변

### monitor.sh 명령 선택과 파싱 방식

- 프로세스 식별은 `ps -eo pid=,comm=,args=`와 `awk`를 사용한다. `pgrep -f`는 자기 자신(`monitor.sh`, `grep`, `awk`)을 잡기 쉬워 오탐 가능성이 있으므로, 현재 PID와 부모 PID, 모니터링 관련 프로세스를 제외하고 `agent-app` 또는 `agent_app.py` 패턴만 선택한다.
- 포트 확인은 `ss -H -ltn`을 사용한다. `ss`는 최신 리눅스에서 `netstat`보다 기본 도구에 가깝고, `LISTEN` TCP 소켓을 직접 확인할 수 있어 포트 `15034`가 실제로 열렸는지 검증하기 적합하다.
- CPU는 `/proc/stat`의 전체 CPU tick을 1초 간격으로 두 번 읽고, `100 * (total_delta - idle_delta) / total_delta`로 계산한다. 메모리는 `/proc/meminfo`의 `MemTotal`과 `MemAvailable` 차이로 계산한다. 디스크는 `df -P /`의 root partition 사용률을 사용한다.
- 로그 포맷은 `[YYYY-MM-DD HH:MM:SS] PID:... CPU:..% MEM:..% DISK_USED:..%`로 고정했다. `report.sh`가 timestamp, CPU, MEM, DISK 값을 안정적으로 파싱해야 하므로 키 이름과 순서를 일정하게 유지한다.

### 권한 정책과 로그 관리

- `monitor.sh`의 소유자는 `agent-dev`, 그룹은 `agent-core`, 권한은 `750`이다. 작성 책임은 개발/운영 역할인 `agent-dev`에 두고, 실행 권한은 `agent-core` 그룹에만 열어 `agent-admin` cron이 실행할 수 있게 했다.
- `agent-test`는 `agent-common`에만 포함되어 `upload_files`에는 접근할 수 있지만, `api_keys`와 `/var/log/agent-app`에는 접근할 수 없다. 키와 운영 로그는 장애 원인 및 인증 정보에 가까우므로 최소 권한 원칙에 따라 `agent-core`로 제한한다.
- `monitor.log`는 스크립트 내부 회전 로직으로 관리한다. 기본값은 `MAX_LOG_BYTES=10485760`(10MB)이고, active 파일 1개와 rotated 파일 9개를 유지해 총 10개 파일 정책을 만족한다. 오래된 rotated 파일은 수정 시간 기준으로 초과분을 삭제한다.
- 추가 보존 정책은 `archive_logs.sh`에서 수행한다. 7일 이상 지난 `/var/log/agent-app/*.log`를 gzip으로 압축해 `/var/log/monitor/agent-app/archive/`로 이동하고, 30일 이상 지난 `.gz` 아카이브를 삭제한다. 디렉토리 미존재, 권한 부족, 대상 파일 0개는 오류로 중단하지 않고 경고 또는 정보 메시지로 종료한다.

### 보안과 운영 판단

- SSH 포트를 `20022`로 바꾸면 기본 포트 `22`를 대상으로 하는 자동 스캔과 무차별 대입 시도의 노출을 줄일 수 있다. Root 원격 접속 차단은 단일 최고권한 계정 탈취 위험을 낮추며, 일반 계정 로그인 후 필요한 경우에만 권한 상승하도록 강제한다.
- 방화벽은 inbound 기본 deny 상태에서 `20022/tcp`, `15034/tcp`만 허용한다. 이는 SSH 관리 경로와 앱 서비스 경로 외의 불필요한 네트워크 진입점을 제거하는 정책이다.
- 프로세스와 포트 실패는 서비스가 실제로 동작하지 않는 상태이므로 `exit 1`로 종료한다. 반면 방화벽 비활성이나 CPU/MEM/DISK 임계값 초과는 즉시 관제 데이터 기록 자체를 중단할 사유는 아니므로 `[WARNING]`만 출력하고 로그는 계속 남긴다.
- 리다이렉션 `>`는 파일을 새로 덮어쓰고, `>>`는 파일 끝에 추가한다. 모니터링 로그는 시간 순서대로 누적되어야 하므로 `monitor.log` 기록과 cron 출력에는 `>>`가 필요하다.

### 장애 시나리오 대응

- 모니터링 대상이 Nginx 같은 웹 서버로 바뀌면 `AGENT_PROCESS_PATTERN`, `AGENT_PORT`, 로그 경로, 임계값을 바꾼다. 예를 들어 Nginx는 프로세스 패턴을 `nginx`, 포트를 `80` 또는 `443`, 로그 확인 대상을 `/var/log/nginx` 계열로 변경한다.
- 프로세스는 살아 있는데 포트가 열리지 않는 경우에는 애플리케이션 바인딩 주소/포트 설정, 권한 문제, 포트 충돌, 방화벽/네트워크 네임스페이스, 앱 내부 초기화 실패 순서로 확인한다. `ps`, `ss -ltnp`, 앱 콘솔 로그, 방화벽 상태를 함께 본다.
- 로그 급증으로 디스크가 찰 위험이 있으면 단기적으로 로그 회전 임계값을 낮추고 오래된 로그를 압축/삭제한다. 중기적으로는 로그 레벨 조정, 반복 오류 원인 제거, 별도 로그 저장소 또는 모니터링 시스템 연동을 적용한다.
