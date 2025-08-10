package com.example.postservice;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

@Slf4j
@Component
@RequiredArgsConstructor
public class UserClient {

    private final RestTemplate restTemplate;

    private static final String USER_SERVICE_URL = "http://localhost:8080/users/";

    public String getUserName(Long userId) {
        // =======================
        // 아래 코드 중 하나만 주석 해제하여 전략 적용
        // =======================

        // return strategyA(userId);
        // return strategyB(userId);
        // return strategyC(userId);
        return strategyD(userId);
    }

    @SuppressWarnings("unused") // 전략 선택을 위한 메소드
    private String strategyA(Long userId) {
        try {
            ResponseEntity<UserResponse> response = restTemplate.getForEntity(USER_SERVICE_URL + userId,
                    UserResponse.class);
            UserResponse body = response.getBody();
            return body != null ? body.getName() : null;
        } catch (Exception e) {
            log.error("UserService 호출 실패", e);
            return null;
        }
    }

    @SuppressWarnings("unused") // 전략 선택을 위한 메소드
    private String strategyB(Long userId) {
        try {
            ResponseEntity<UserResponse> response = restTemplate.getForEntity(USER_SERVICE_URL + userId,
                    UserResponse.class);
            UserResponse body = response.getBody();
            return body != null ? body.getName() : "Unknown User";
        } catch (Exception e) {
            log.warn("UserService 호출 실패 – 기본값 반환");
            return "Unknown User";
        }
    }

    @SuppressWarnings("unused") // 전략 선택을 위한 메소드
    private String strategyC(Long userId) {
        ResponseEntity<UserResponse> response = restTemplate.getForEntity(USER_SERVICE_URL + userId,
                UserResponse.class);
        UserResponse body = response.getBody();
        if (body == null) {
            throw new RuntimeException("UserService에서 null 응답을 받았습니다.");
        }
        return body.getName(); // 실패 시 예외 그대로 터짐
    }

    private String strategyD(Long userId) {
        int retryCount = 0;
        while (retryCount < 3) {
            try {
                ResponseEntity<UserResponse> response = restTemplate.getForEntity(USER_SERVICE_URL + userId,
                        UserResponse.class);
                UserResponse body = response.getBody();
                if (body != null) {
                    return body.getName();
                }
            } catch (Exception e) {
                retryCount++;
                log.warn("UserService 호출 실패 - {}회차 재시도", retryCount);
                try {
                    Thread.sleep(500);
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
        }
        log.error("UserService 재시도 실패 – 기본값 반환");
        return "Unknown User";
    }

    static class UserResponse {
        private Long id;
        private String name;

        public Long getId() {
            return id;
        }

        public void setId(Long id) {
            this.id = id;
        }

        public String getName() {
            return name;
        }

        public void setName(String name) {
            this.name = name;
        }
    }
}
