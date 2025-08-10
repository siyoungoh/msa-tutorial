## 파일 설명

이 디렉터리는 프로젝트용 보조 스크립트를 담고 있습니다. 핵심 스크립트는 `verify.sh`이며, Spring Boot 애플리케이션이 정상 빌드/기동되는지 자동으로 검증합니다.

### 목적
- 프로젝트 빌드(`./gradlew clean build -x test`)
- 부팅 가능한 JAR 선택(`build/libs` 내 `-plain.jar` 제외)
- 애플리케이션 백그라운드 기동 후 `/actuator/health`가 `UP`이 될 때까지 대기
- 최근 로그 출력 후 애플리케이션 종료

### 위치
- `msa/scripts/verify.sh`

### 사용법
```bash
# 기본 포트(8080)에서 검증 실행
./scripts/verify.sh

# 포트 변경
PORT=8081 ./scripts/verify.sh

# JVM 옵션 추가
JAVA_OPTS="-Xms256m -Xmx512m" ./scripts/verify.sh

# Gradle 옵션 전달 (예: 데몬 비활성화)
GRADLE_OPTS="--no-daemon" ./scripts/verify.sh

# 호스트/URL 오버라이드
# 전체 URL 직접 지정(최우선)
HEALTH_URL="http://my-host:8080/actuator/health" ./scripts/verify.sh
# 또는 구성 요소별 지정
VERIFY_SCHEME=https VERIFY_HOST=my-host PORT=8443 HEALTH_PATH=/actuator/health ./scripts/verify.sh

# CI 모드(더 짧은 타임아웃, 성공 시 로그 자동 삭제)
VERIFY_CI=true ./scripts/verify.sh
# 성공 로그 유지하려면
VERIFY_CI=true VERIFY_KEEP_LOGS=true ./scripts/verify.sh
```

### 간단 버전(verify-min.sh)
보다 짧고 단순한 검증이 필요하면 다음 스크립트를 사용할 수 있습니다.

```bash
# 최소 검증 실행 (bootJar만 빌드 → 기동 → health 확인)
./scripts/verify-min.sh

# 포트/JVM/Gradle 옵션 동일하게 지원
PORT=8081 ./scripts/verify-min.sh
JAVA_OPTS="-Xms256m -Xmx512m" ./scripts/verify-min.sh
GRADLE_OPTS="--no-daemon" ./scripts/verify-min.sh

# 호스트/URL 오버라이드
HEALTH_URL="http://my-host:8080/actuator/health" ./scripts/verify-min.sh
VERIFY_SCHEME=https VERIFY_HOST=my-host PORT=8443 HEALTH_PATH=/actuator/health ./scripts/verify-min.sh

# CI 모드(더 짧은 타임아웃, 성공 시 로그 자동 삭제)
VERIFY_CI=true ./scripts/verify-min.sh
# 성공 로그 유지하려면
VERIFY_CI=true VERIFY_KEEP_LOGS=true ./scripts/verify-min.sh
```

### 두 버전 비교
- **verify.sh**: 
  - 전체 빌드(`clean build -x test`) 수행
  - 포트 점유 사전 검사(`lsof`)로 충돌 예방
  - 부팅 가능한 JAR 선택 시 `-plain.jar` 제외 및 스냅샷 우선
  - 헬스체크 대기(최대 60초, 1초 간격), 성공 시 최근 로그 50줄 출력
  - 로그 파일: `build/verify-app.log`

- **verify-min.sh**:
  - 최소 빌드(`bootJar`만 실행)로 속도 우선
  - 포트 점유 검사 생략(바로 기동 시도)
  - JAR 선택 단순화(`-plain.jar`만 제외)
  - 헬스체크 대기(최대 60초, 1초 간격), 성공 시 최근 로그 30줄 출력
  - 로그 파일: `build/verify-min.log`

### CI 권장 사항
- 기본적으로 CI 환경에서는 속도와 단순성을 위해 **`verify-min.sh` 사용을 권장**합니다.
- 보수적 검증(전체 빌드, 포트 충돌 사전 방지)이 필요한 스테이지에서는 `verify.sh` 사용을 고려하세요.

### 로그 파일
- 경로: `build/verify-app.log`

### 종료 코드
- `0`: 검증 성공(health == UP)
- `1`: 실패(빌드 실패, 포트 점유, JAR 미발견, 헬스체크 타임아웃 등)

### 참고
- `/actuator/health` 확인을 위해 `actuator` 의존성이 필요합니다.
- 기본 포트 `8080`이 사용 중이면 `PORT` 환경변수로 다른 포트를 지정하세요.
