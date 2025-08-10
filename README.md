# Block 2: Docker 환경 전환 실습 안내

간단한 게시판-회원 MSA 목업 구성입니다.
- PostService(8080): 게시글 API 제공. 사용자 이름 조회 시 UserService를 호출
- UserService(8081): 사용자 API 제공. `GET /users/{id}`로 사용자 이름 반환
- 통신 실패 시 PostService는 제한적 폴백(예: "Unknown User")을 적용

## 프로젝트 목적
- **MSA 환경에서 발생할 수 있는 네트워크 통신 오류**에 대해 여러 전략을 탐색(A/B/C/D)
- **Docker**로 컨테이너 네트워크를 구성하여 MSA와 유사한 실행/배포 흐름을 체험
- 도메인 로직 복잡도는 줄이고 통신 흐름에 집중하기 위해 **목업**으로 구성

## 네트워크 통신 실패 전략(A/B/C/D)
- A(로그만): `try-catch`로 오류를 잡고 로그만 남김. 사용자 응답은 성공처럼 보일 수 있으나 데이터 누락 위험 존재
- B(기본값 폴백): 오류 시 제한적 기본값 반환(예: "Unknown User"). 사용자 경험은 유지되나 정확도 저하
- C(오류 전파): 오류를 클라이언트에 그대로 노출(5xx/메시지). 정확하지만 사용자 경험 저하
- D(재시도/백오프/서킷브레이커): 일시 오류를 자동 흡수. 최종 실패 시 B 또는 C와 조합

적용 지점(예시)
- `msa/postservice/src/main/java/com/example/postservice/UserClient.java` 내부 외부 호출부
  - 현재 예시는 B(D 일부 개념) 형태의 **제한적 폴백**을 기본값으로 사용
  - C 실험을 원하면 오류 시 예외를 던지도록 변경하여 5xx가 반환되게 할 수 있음

## 1. 포트 설정
- `msa/userservice/src/main/resources/application.yml`: 8081
- `msa/postservice/src/main/resources/application.yml`: 8080 및 `userservice.base-url: http://userservice:8081`

## 2. Dockerfile 위치(모듈 별 이미지화)
- `msa/userservice/Dockerfile`
- `msa/postservice/Dockerfile`

예시(Dockerfile 공통)
```
FROM openjdk:17
ARG JAR_FILE=build/libs/*.jar
COPY ${JAR_FILE} app.jar
ENTRYPOINT ["java", "-jar", "app.jar"]
```

## 3. 컨테이너 네트워크
- 네트워크 이름: `msa-net`
- 컨테이너 이름: `userservice`, `postservice`
- PostService → UserService 호출 주소: `http://userservice:8081`

## 4. 자동 빌드/실행 스크립트
- `scripts/docker-multi.sh`
  - 모듈 JAR 빌드 → 각 모듈 Dockerfile로 이미지 빌드
  - `msa-net` 생성 후 컨테이너 기동(8081/8080)
  - 정상 호출 및 userservice 중단 후 폴백 동작 확인

실행
```
bash scripts/docker-multi.sh
```

주의: 호스트 8081 포트를 이미 사용 중이라면 바인딩이 실패할 수 있습니다. 이 경우 userservice의 `-p 8081:8081` 바인딩을 제거해 내부 통신만으로 확인하거나, 사용 중인 프로세스를 종료하세요.

## 5. 애플리케이션 설정(내부 DNS)
- PostService 설정(`msa/postservice/src/main/resources/application.yml`):
  - `userservice.base-url: http://userservice:8081`
- PostService의 `UserClient`는 위 설정을 사용하여 `http://userservice:8081/users/{id}`로 호출합니다.

## 6. 통신 확인 테스트
- `src/test/post-check.http` 활용
  - 정상: `GET http://localhost:8080/posts/1`
  - 실패 실험: userservice 컨테이너 중단 후 동일 요청
  - 관찰 포인트: B/D 계열이면 `authorName: "Unknown User"`, C 계열이면 5xx 응답

## 7. 스크립트 사용(멀티모듈 기준)
- 파일: `scripts/docker-multi.sh`
- 기능: 모듈 JAR 빌드 → 모듈 Dockerfile로 이미지 빌드 → 컨테이너 실행 → 통신 검증

환경변수
- `PUBLISH`: true|false (기본 true). false면 호스트 포트 바인딩 생략
- `VERIFY_HOST`: 검증 대상 호스트/IP (기본 localhost)
- `VERIFY_POST_PORT`: 검증 대상 PostService 포트 (기본 8080)

예시
```
# 로컬 기본 실행(8080/8081 공개, localhost 검증)
bash scripts/docker-multi.sh

# 원격 호스트 검증(예: 20.30.40.50:80)
VERIFY_HOST=20.30.40.50 VERIFY_POST_PORT=80 bash scripts/docker-multi.sh

# 내부 네트워크만 사용(포트 공개 생략)
PUBLISH=false bash scripts/docker-multi.sh
```



