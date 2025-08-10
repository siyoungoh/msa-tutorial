package com.example.postservice;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/posts")
public class PostController {

    private final UserClient userClient;

    public PostController(UserClient userClient) {
        this.userClient = userClient;
    }

    @GetMapping
    public List<PostDto> getPosts() {
        return List.of(
                new PostDto(1L, "Hello World", userClient.getUserName(1L)),
                new PostDto(2L, "Second Post", userClient.getUserName(2L)));
    }
}
