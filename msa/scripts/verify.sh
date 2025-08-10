#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# verify.sh
#
# Purpose:
#   Build the Spring Boot project, start the packaged JAR on a given port,
#   wait until the Actuator health endpoint reports UP, then stop the app.
#
# Usage:
#   ./scripts/verify.sh
#   PORT=8081 ./scripts/verify.sh
#   JAVA_OPTS="-Xms256m -Xmx512m" ./scripts/verify.sh
#   GRADLE_OPTS="--no-daemon" ./scripts/verify.sh
#
# Behavior:
#   - Runs: ./gradlew clean build -x test
#   - Picks the bootable JAR (excludes "-plain.jar") under build/libs
#   - Starts the app in background with nohup and waits for /actuator/health UP
#   - Prints recent logs and gracefully stops the app
#
# Environment Variables:
#   PORT        : HTTP port to run the app on (default: 8080)
#   JAVA_OPTS   : Extra JVM options for the java -jar command
#   GRADLE_OPTS : Extra options passed to the Gradle command
#   VERIFY_CI   : If "true", enable CI mode (shorter timeout, auto-log cleanup)
#   VERIFY_KEEP_LOGS : If "true" and CI mode, keep logs on success
#   HEALTH_URL  : If set, use as full health endpoint URL
#   VERIFY_SCHEME : http or https (default: http)
#   VERIFY_HOST : Hostname for health check (default: localhost)
#   HEALTH_PATH : Health endpoint path (default: /actuator/health)
#
# Exit Codes:
#   0 : Verification succeeded (health == UP)
#   1 : Any failure (build failure, jar not found, port busy, health timeout, etc.)
# -----------------------------------------------------------------------------
set -euo pipefail

# Resolve and move to project root (one level above this script directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

# Configuration with sensible defaults
PORT="${PORT:-8080}"
JAVA_OPTS="${JAVA_OPTS:-}"
GRADLE_OPTS="${GRADLE_OPTS:-}"

echo "[verify] Project root: ${PROJECT_ROOT}"
echo "[verify] Using port: ${PORT}"
# Detect CI mode
CI_MODE=false
if [[ "${VERIFY_CI:-}" == "true" || "${CI:-}" == "true" ]]; then
  CI_MODE=true
fi

# Fail early if port is already in use (if lsof is available)
if command -v lsof >/dev/null 2>&1; then
  if lsof -i TCP:"${PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "[verify][error] Port ${PORT} is already in use. Set PORT env or free the port."
    exit 1
  fi
fi

# Ensure Gradle wrapper is executable and build without tests
chmod +x ./gradlew
./gradlew ${GRADLE_OPTS} clean build -x test | cat

# Select the bootable JAR (exclude "-plain.jar")
JAR_PATH=""
if compgen -G "build/libs/*-SNAPSHOT.jar" > /dev/null; then
  JAR_PATH="$(ls build/libs/*-SNAPSHOT.jar | grep -v -- '-plain\.jar' | head -n 1)"
fi
if [[ -z "${JAR_PATH}" || ! -f "${JAR_PATH}" ]]; then
  # fallback: any jar except -plain
  if compgen -G "build/libs/*.jar" > /dev/null; then
    JAR_PATH="$(ls build/libs/*.jar | grep -v -- '-plain\.jar' | head -n 1)"
  fi
fi

if [[ -z "${JAR_PATH}" || ! -f "${JAR_PATH}" ]]; then
  echo "[verify][error] Bootable jar not found under build/libs."
  ls -al build/libs || true
  exit 1
fi

echo "[verify] Using jar: ${JAR_PATH}"

# Prepare log file
LOG_FILE="${PROJECT_ROOT}/build/verify-app.log"
rm -f "${LOG_FILE}" || true

echo "[verify] Starting application..."
set +e
# Start the application on the requested port in the background
nohup java ${JAVA_OPTS} -jar "${JAR_PATH}" --server.port="${PORT}" > "${LOG_FILE}" 2>&1 &
APP_PID=$!
set -e

# Ensure the app is stopped when the script exits
cleanup() {
  if ps -p "${APP_PID}" >/dev/null 2>&1; then
    echo "[verify] Stopping application (pid=${APP_PID})"
    kill "${APP_PID}" 2>/dev/null || true
    # give it a moment to stop
    sleep 2
  fi
}
trap cleanup EXIT

echo "[verify] Waiting for health endpoint to be UP..."
# Probe the Actuator health endpoint until it reports status=UP
# Build health URL with overrides
VERIFY_SCHEME="${VERIFY_SCHEME:-http}"
VERIFY_HOST="${VERIFY_HOST:-localhost}"
HEALTH_PATH="${HEALTH_PATH:-/actuator/health}"
HEALTH_URL="${HEALTH_URL:-${VERIFY_SCHEME}://${VERIFY_HOST}:${PORT}${HEALTH_PATH}}"
DEFAULT_ATTEMPTS=60
${CI_MODE} && DEFAULT_ATTEMPTS=30 || true
ATTEMPTS="${ATTEMPTS:-${DEFAULT_ATTEMPTS}}"
SLEEP_SEC=1
for ((i=1; i<=ATTEMPTS; i++)); do
  # Use a portable grep class for whitespace to avoid BSD grep option pitfalls
  if curl -fsS "${HEALTH_URL}" | grep -Eq '"status"[[:space:]]*:[[:space:]]*"UP"'; then
    echo "[verify] Health check success: UP"
    echo "[verify] Logs (last 50 lines):"
    tail -n 50 "${LOG_FILE}" || true
    # In CI mode, delete logs on success unless explicitly kept
    if ${CI_MODE} && [[ "${VERIFY_KEEP_LOGS:-false}" != "true" ]]; then
      rm -f "${LOG_FILE}" || true
    fi
    exit 0
  fi
  if ! ps -p "${APP_PID}" >/dev/null 2>&1; then
    echo "[verify][error] Application process exited unexpectedly. See logs: ${LOG_FILE}"
    tail -n 200 "${LOG_FILE}" || true
    exit 1
  fi
  sleep "${SLEEP_SEC}"
done

echo "[verify][error] Health check failed within $((ATTEMPTS*SLEEP_SEC))s. URL: ${HEALTH_URL}"
echo "[verify] Logs (last 200 lines):"
tail -n 200 "${LOG_FILE}" || true
exit 1


