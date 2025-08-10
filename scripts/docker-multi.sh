#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR/msa"

echo "[1/5] Build JAR"
./gradlew -q clean bootJar -x test

POST_DIR="$ROOT_DIR/PostService/build/libs"
USER_DIR="$ROOT_DIR/UserService/build/libs"
mkdir -p "$POST_DIR" "$USER_DIR"

echo "[2/5] Copy JAR to module folders"
cp build/libs/msa-0.0.1-SNAPSHOT.jar "$POST_DIR/app.jar"
cp build/libs/msa-0.0.1-SNAPSHOT.jar "$USER_DIR/app.jar"

echo "[3/5] Build images"
cd "$ROOT_DIR/PostService" && docker build -t postservice:module .
cd "$ROOT_DIR/UserService" && docker build -t userservice:module .

echo "[4/5] Run containers"
docker network create msa-net 2>/dev/null || true
docker rm -f userservice postservice 2>/dev/null || true
docker run -d --name userservice --network msa-net -p 8081:8081 userservice:module
docker run -d --name postservice --network msa-net -p 8080:8080 postservice:module

echo "[5/5] Verify"
sleep 3
echo "== Success check =="
curl -sS http://localhost:8080/posts | cat; echo
echo "\n== Stop userservice and check fallback =="
docker stop userservice >/dev/null
sleep 2
curl -sS http://localhost:8080/posts | cat; echo


