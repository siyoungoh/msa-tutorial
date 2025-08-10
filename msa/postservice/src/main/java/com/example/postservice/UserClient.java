package com.example.postservice;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

@Slf4j
@Component
@RequiredArgsConstructor
public class UserClient {

    private final RestTemplate restTemplate;

    @Value("${userservice.base-url:http://userservice:8081}")
    private String userServiceBaseUrl;

    private String getUserUrl(Long userId) {
        String base = userServiceBaseUrl.endsWith("/")
                ? userServiceBaseUrl.substring(0, userServiceBaseUrl.length() - 1)
                : userServiceBaseUrl;
        return base + "/users/" + userId;
    }

    public String getUserName(Long userId) {
        try {
            ResponseEntity<UserResponse> response = restTemplate.getForEntity(getUserUrl(userId), UserResponse.class);
            UserResponse body = response.getBody();
            return body != null ? body.getName() : "Unknown User";
        } catch (Exception e) {
            log.warn("UserService 호출 실패 – 기본값 반환");
            return "Unknown User";
        }
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
