#!/usr/bin/env bash
# verify-min.sh — Minimal verification script
# - Builds only the bootable JAR
# - Starts the app on PORT
# - Waits for /actuator/health to be UP
# - Stops the app and prints recent logs
#
# CI mode (set VERIFY_CI=true or CI=true):
# - Faster default timeout (ATTEMPTS=30 instead of 60)
# - On success, delete log file unless VERIFY_KEEP_LOGS=true
#
# Host/URL override:
# - If HEALTH_URL is set, use it directly
# - Else, build from VERIFY_SCHEME (default http), VERIFY_HOST (default localhost), PORT, HEALTH_PATH (default /actuator/health)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

PORT="${PORT:-8080}"
JAVA_OPTS="${JAVA_OPTS:-}"
GRADLE_OPTS="${GRADLE_OPTS:-}"

# Detect CI mode
CI_MODE=false
if [[ "${VERIFY_CI:-}" == "true" || "${CI:-}" == "true" ]]; then
  CI_MODE=true
fi

echo "[verify-min] Building bootJar..."
chmod +x ./gradlew
./gradlew ${GRADLE_OPTS} -q bootJar

JAR_PATH="$(ls -1 build/libs/*.jar 2>/dev/null | grep -v -- '-plain\.jar' | head -n 1 || true)"
if [[ -z "${JAR_PATH}" || ! -f "${JAR_PATH}" ]]; then
  echo "[verify-min][error] Bootable jar not found under build/libs."
  ls -al build/libs || true
  exit 1
fi

LOG_FILE="${ROOT_DIR}/build/verify-min.log"
rm -f "${LOG_FILE}" || true

echo "[verify-min] Starting application on port ${PORT}..."
set +e
nohup java ${JAVA_OPTS} -jar "${JAR_PATH}" --server.port="${PORT}" > "${LOG_FILE}" 2>&1 &
PID=$!
set -e

cleanup() {
  if ps -p "${PID}" >/dev/null 2>&1; then
    kill "${PID}" 2>/dev/null || true
    sleep 1
  fi
}
trap cleanup EXIT

# Build health URL with overrides
VERIFY_SCHEME="${VERIFY_SCHEME:-http}"
VERIFY_HOST="${VERIFY_HOST:-localhost}"
HEALTH_PATH="${HEALTH_PATH:-/actuator/health}"
HEALTH_URL="${HEALTH_URL:-${VERIFY_SCHEME}://${VERIFY_HOST}:${PORT}${HEALTH_PATH}}"

# Attempts: default 60, CI mode default 30 (override with ATTEMPTS env)
DEFAULT_ATTEMPTS=60
${CI_MODE} && DEFAULT_ATTEMPTS=30 || true
ATTEMPTS="${ATTEMPTS:-${DEFAULT_ATTEMPTS}}"

for ((i=1; i<=ATTEMPTS; i++)); do
  if curl -fsS "${HEALTH_URL}" | grep -Eq '"status"[[:space:]]*:[[:space:]]*"UP"'; then
    echo "[verify-min] Health check: UP"
    tail -n 30 "${LOG_FILE}" || true
    # In CI mode, delete logs on success unless explicitly kept
    if ${CI_MODE} && [[ "${VERIFY_KEEP_LOGS:-false}" != "true" ]]; then
      rm -f "${LOG_FILE}" || true
    fi
    exit 0
  fi
  if ! ps -p "${PID}" >/dev/null 2>&1; then
    echo "[verify-min][error] Application process exited unexpectedly. See logs: ${LOG_FILE}"
    tail -n 200 "${LOG_FILE}" || true
    exit 1
  fi
  sleep 1
done

echo "[verify-min][error] Health check timed out (${ATTEMPTS}s). URL: ${HEALTH_URL}"
tail -n 200 "${LOG_FILE}" || true
exit 1


