# Block 2: Docker 환경 전환 실습 안내

이 실습은 PostService(8080) ↔ UserService(8081)를 컨테이너 네트워크에서 통신하도록 구성하고, 장애 시 폴백 동작을 확인합니다.

## 1. 포트 설정
- `UserService/src/main/resources/application.yml`: 8081
- `PostService/src/main/resources/application.yml`: 8080

## 2. Dockerfile 위치(모듈 별 이미지화)
- `UserService/Dockerfile`
- `PostService/Dockerfile`

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
  - 단일 JAR 빌드 → 각 모듈 `build/libs/app.jar`에 복사 → 각 모듈 Dockerfile로 이미지 빌드
  - `msa-net` 생성 후 컨테이너 기동(8081/8080)
  - 정상 호출 및 userservice 중단 후 폴백 동작 확인

실행
```
bash scripts/docker-multi.sh
```

주의: 호스트 8081 포트를 이미 사용 중이라면 바인딩이 실패할 수 있습니다. 이 경우 userservice의 `-p 8081:8081` 바인딩을 제거해 내부 통신만으로 확인하거나, 사용 중인 프로세스를 종료하세요.

## 5. 애플리케이션 설정(내부 DNS)
- `msa/src/main/resources/application.yml`에 기본값 존재:
  - `userservice.base-url: http://userservice:8081`
- `UserClient`는 위 설정을 사용하여 `http://userservice:8081/users/{id}`로 호출합니다.

## 6. 통신 확인 테스트
- `src/test/post-check.http` 활용
  - 정상: `GET http://localhost:8080/posts/1`
  - 실패 실험: userservice 컨테이너 중단 후 동일 요청

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



