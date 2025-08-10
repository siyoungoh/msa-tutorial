#!/usr/bin/env bash
#
# UserClient 통합 테스트 자동화 스크립트
# - 정상 동작(8080) 시나리오와 장애(8081) 시나리오를 자동으로 빌드/기동/검증합니다.
# - 로컬 또는 원격 호스트에 대해 헬스체크 폴링과 엔드포인트 호출을 수행합니다.
#
# 사용 예시
#   - 성공만:       bash msa/scripts/test-userclient.sh success
#   - 실패만:       bash msa/scripts/test-userclient.sh failure
#   - 둘 다:        bash msa/scripts/test-userclient.sh both
#   - 빌드만:       bash msa/scripts/test-userclient.sh build
#   - 종료:         bash msa/scripts/test-userclient.sh stop
#   - 헬스 폴링:    TARGET_HOST=10.0.0.5 bash msa/scripts/test-userclient.sh poll 8081
#
# 환경 변수
#   - APP_JAR:     테스트할 부팅 가능한 JAR 경로 (기본: build/libs/msa-0.0.1-SNAPSHOT.jar)
#   - TARGET_HOST: 테스트 대상 호스트 (기본: localhost)
#   - STRATEGY:    현재 선택된 전략(A|B|C|D). C일 때 장애 시나리오는 5xx 기대로 처리(정상은 성공 기대)
#   - EXPECT_FALLBACK: 실패 시 기대 값(기본: Unknown User, A일 때 __NULL__ 권장)
#
# 전략별 실행 예시
#   - Strategy A: EXPECT_FALLBACK='__NULL__' bash msa/scripts/test-userclient.sh both
#   - Strategy B: bash msa/scripts/test-userclient.sh both
#   - Strategy C: STRATEGY=C bash msa/scripts/test-userclient.sh both
#   - Strategy D: bash msa/scripts/test-userclient.sh both
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# 대상 JAR과 테스트 대상 호스트는 환경변수로 오버라이드 가능
# 예) APP_JAR=/path/to/other.jar TARGET_HOST=192.168.0.10 bash scripts/test-userclient.sh success
APP_JAR="${APP_JAR:-build/libs/msa-0.0.1-SNAPSHOT.jar}"
TARGET_HOST="${TARGET_HOST:-localhost}"
## 실패 시 기대하는 폴백 값 설정
## - 기본: "Unknown User" (Strategy B/D)
## - Strategy A에서 null 기대 시: EXPECT_FALLBACK="__NULL__"
EXPECT_FALLBACK="${EXPECT_FALLBACK:-Unknown User}"
STRATEGY="${STRATEGY:-}"

log() { echo "[$(date '+%H:%M:%S')] $*"; }  # 타임스탬프 로그 출력

build() {
  # Gradle로 부팅 가능한 JAR 생성
  log "Building jar..."
  ./gradlew bootJar -x test | cat
}

wait_up() {
  # 지정 포트의 /actuator/health 를 최대 40초 동안 폴링하여 기동 여부 확인
  local port="$1"
  for i in {1..40}; do
    if curl -sS "http://${TARGET_HOST}:${port}/actuator/health" >/dev/null 2>&1; then
      log "App is up on port ${port}"
      return 0
    fi
    sleep 1
  done
  log "App did not start on port ${port}"
  tail -n 80 "app_${port}.out" || true
  exit 1
}

run_port() {
  # 로컬 호스트일 때만 애플리케이션을 실제로 기동
  # 원격 호스트(TARGET_HOST != localhost)인 경우에는 기동 생략하고 폴링/검증만 수행
  local port="$1"
  if [[ "${TARGET_HOST}" == "localhost" || "${TARGET_HOST}" == "127.0.0.1" ]]; then
    log "Starting app on port ${port} (HOST=${TARGET_HOST})..."
    pkill -f "msa-0.0.1-SNAPSHOT.jar --server.port=${port}" >/dev/null 2>&1 || true
    pkill -f "msa-0.0.1-SNAPSHOT.jar" >/dev/null 2>&1 || true
    nohup java -jar "$APP_JAR" --server.port="${port}" > "app_${port}.out" 2>&1 & echo $! > "app_${port}.pid"
  else
    log "Skipping local start since TARGET_HOST=${TARGET_HOST}. Will only poll/check remote."
  fi
  wait_up "$port"
}

stop_all() {
  # 실행 중인 인스턴스 종료 및 PID 파일 정리
  log "Stopping any running app instances..."
  for f in app_*.pid; do
    [ -f "$f" ] || continue
    kill "$(cat "$f")" >/dev/null 2>&1 || true
    rm -f "$f"
  done
  pkill -f "msa-0.0.1-SNAPSHOT.jar" >/dev/null 2>&1 || true
}

test_success() {
  # 정상 시나리오: 8080에서 /users/1, /posts 호출 시 폴백("Unknown User")가 없어야 함
  local port=8080
  run_port "$port"
  log "Testing success scenario on ${port}..."
  echo "== /users/1 =="
  curl -sS "http://${TARGET_HOST}:${port}/users/1" || true
  echo
  echo "== /posts =="
  local resp
  resp="$(curl -sS "http://${TARGET_HOST}:${port}/posts")"
  echo "$resp"
  if grep -q "Unknown User" <<<"$resp"; then
    log "Unexpected fallback detected in success scenario"
    exit 1
  else
    log "Success scenario OK"
  fi
}

test_failure() {
  # 실패 시나리오: 8081에서 /posts 호출 시 폴백("Unknown User")가 나와야 함
  local port=8081
  run_port "$port"
  log "Testing failure scenario on ${port} (fallback expected)..."
  echo "== /posts (failure expected) =="
  if [[ "${STRATEGY}" == "C" ]]; then
    # Strategy C: 실패 시 예외 전파 → API 5xx 기대
    local code
    code="$(curl -sS -o /dev/null -w "%{http_code}" "http://${TARGET_HOST}:${port}/posts" || true)"
    echo "HTTP ${code}"
    if [[ "$code" == 5* || "$code" == "000" ]]; then
      log "Strategy C expected failure (5xx) OK"
    else
      log "Strategy C expected 5xx, but got ${code}"
      exit 1
    fi
  else
    local resp
    resp="$(curl -sS "http://${TARGET_HOST}:${port}/posts")"
    echo "$resp"
    if [[ "$EXPECT_FALLBACK" == "__NULL__" ]]; then
      if grep -q '"authorName":null' <<<"$resp"; then
        log "Fallback (null) OK in failure scenario"
      else
        log "Fallback (null) NOT applied"
        exit 1
      fi
    else
      if grep -q "${EXPECT_FALLBACK}" <<<"$resp"; then
        log "Fallback (${EXPECT_FALLBACK}) OK in failure scenario"
      else
        log "Fallback (${EXPECT_FALLBACK}) NOT applied"
        exit 1
      fi
    fi
  fi
}

usage() {
  cat <<USAGE
Usage: scripts/test-userclient.sh {build|success|failure|both|stop|poll <port>}
  build    Build the bootable jar
  success  Run on 8080 and verify normal responses (no fallback)
  failure  Run on 8081 and verify fallback (Unknown User)
  both     Run success then failure tests
  stop     Stop any running instances
  poll     Poll health endpoint on the given port (one-liner equivalent)

Environment variables:
  APP_JAR     Path to bootable jar (default: build/libs/msa-0.0.1-SNAPSHOT.jar)
  TARGET_HOST Target host to test against (default: localhost)
USAGE
}

cmd="${1:-}"
case "$cmd" in
  build) build ;;
  success) build; test_success ;;
  failure) build; test_failure ;;
  both) build; test_success; stop_all; test_failure ;;
  stop) stop_all ;;
  poll)
    # 헬스 폴링 (원라이너 등가):
    # for i in {1..40}; do if curl -sS http://HOST:PORT/actuator/health >/dev/null 2>&1; then echo up; exit 0; else sleep 1; fi; done; echo down; exit 1
    port="${2:-8080}"
    for i in {1..40}; do
      if curl -sS "http://${TARGET_HOST}:${port}/actuator/health" >/dev/null 2>&1; then
        echo up
        exit 0
      else
        sleep 1
      fi
    done
    echo down
    exit 1
    ;;
  *) usage; exit 1 ;;
esac


