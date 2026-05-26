# Linux Agent Monitoring Lab

Docker 기반 Ubuntu 22.04 실습 환경에서 SSH 보안 설정, UFW 방화벽, 계정/그룹/ACL 권한 분리, 앱 상태 관제, 로그 회전, cron 자동 실행을 구성하는 과제 저장소입니다.

## 공개 저장소 구성

이 저장소에는 스크립트, Docker 설정, 과제 문서만 포함합니다.

공개 저장소에 올리지 않는 항목:

- `agent-app.zip`
- `agent-app/` 내부 실행 바이너리
- `.DS_Store`, `q`, 로그, 임시 파일
- `.env` 같은 로컬 설정 파일

`agent-app.zip`은 제공받은 실행 앱 산출물이므로 Git에 포함하지 않습니다. 로컬에서 빌드하려면 제공받은 `agent-app.zip`을 저장소 루트에 둔 뒤 실행하세요.

## 실행

```bash
docker compose up --build
```

상태 확인:

```bash
./bin/lab_status.sh
```

컨테이너 접속:

```bash
docker exec -it agent-lab bash
```

## 주요 파일

- `Dockerfile`: Ubuntu 22.04 기반 실습 환경 구성
- `docker-compose.yml`: 컨테이너 실행 설정
- `docker/entrypoint.sh`: 방화벽, SSH, cron, 앱 실행 진입점
- `bin/monitor.sh`: 프로세스/포트/자원 상태 점검 및 로그 기록
- `bin/report.sh`: `monitor.log` 통계 리포트
- `bin/archive_logs.sh`: 오래된 로그 압축, 이동, 삭제
- `bin/lab_status.sh`: 요구사항 점검 보조 스크립트
- `tests/verify_requirements.sh`: 문서/설정 정적 검증
- `submission-report.md`: 수행 내역서

## 검증

```bash
./tests/verify_requirements.sh
```

Docker 실행 후:

```bash
./bin/lab_status.sh
```

## 주의

Dockerfile의 계정 비밀번호와 앱 키 문자열은 로컬 과제 실습용 기본값입니다. 외부에 노출되는 서버나 실제 운영 환경에서는 그대로 사용하면 안 됩니다.
