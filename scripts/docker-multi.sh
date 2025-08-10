#!/usr/bin/env bash
#
# 멀티모듈(PostService/UserService) Docker 빌드/실행/검증 스크립트
#
# 사용법
# - 로컬 기본 실행(8080/8081 포트 공개, localhost 검증)
#   bash scripts/docker-multi.sh
#
# - 원격 호스트로 검증(예: Azure VM 퍼블릭 IP 20.30.40.50, PostService 외부 포트 80)
#   VERIFY_HOST=20.30.40.50 VERIFY_POST_PORT=80 bash scripts/docker-multi.sh
#
# - 내부 네트워크만 사용(포트 공개 생략). 검증은 별도 환경에서 수행
#   PUBLISH=false bash scripts/docker-multi.sh
#
# 환경변수
# - PUBLISH: true|false (기본 true). false면 -p 포트 바인딩 생략
# - VERIFY_HOST: 검증 대상 호스트명/IP (기본 localhost)
# - VERIFY_POST_PORT: 검증 대상 PostService 포트 (기본 8080)
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR/msa"

echo "[1/4] Build module JARs"
./gradlew -q clean :userservice:bootJar :postservice:bootJar -x test

echo "[2/4] Build images (module Dockerfiles)"
docker build -t userservice:module userservice/
docker build -t postservice:module postservice/

echo "[3/4] Run containers"
docker network create msa-net 2>/dev/null || true
docker rm -f userservice postservice 2>/dev/null || true
# 환경변수로 포트 공개 여부와 검증 대상 호스트/포트를 제어합니다
# PUBLISH=true|false (default true), VERIFY_HOST (default localhost), VERIFY_POST_PORT (default 8080)
PUBLISH=${PUBLISH:-true}
VERIFY_HOST=${VERIFY_HOST:-localhost}
VERIFY_POST_PORT=${VERIFY_POST_PORT:-8080}

if [ "$PUBLISH" = "true" ]; then
  docker run -d --name userservice --network msa-net -p 8081:8081 userservice:module
  docker run -d --name postservice --network msa-net -p 8080:8080 postservice:module
else
  docker run -d --name userservice --network msa-net userservice:module
  docker run -d --name postservice --network msa-net postservice:module
fi

echo "[4/4] Verify"
sleep 3
echo "== Success check =="
curl -sS "http://${VERIFY_HOST}:${VERIFY_POST_PORT}/posts/1" | cat; echo
echo -e "\n== Stop userservice and check fallback =="
docker stop userservice >/dev/null
sleep 2
curl -sS "http://${VERIFY_HOST}:${VERIFY_POST_PORT}/posts/1" | cat; echo


