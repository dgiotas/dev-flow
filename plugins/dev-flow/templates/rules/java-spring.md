---
paths:
  - "**/*.java"
  - "**/src/main/resources/**"
---
<!-- TEMPLATE: verify each line against this repo before keeping it. Delete what doesn't apply. -->
- Keep the layering: controller -> service -> repository. Controllers map HTTP only; transactions (`@Transactional`) belong on service methods.
- Use constructor injection; no field injection. Prefer immutable DTOs (records) at API boundaries; do not expose JPA entities in responses.
- Validate input with Bean Validation (`@Valid`) at controllers; handle errors in one `@ControllerAdvice`, using the repo's existing error format.
- Watch for N+1 queries and lazy-loading outside a transaction; use fetch joins or projections deliberately.
- Config via `application*.yml` and `@ConfigurationProperties`; no secrets in the repo.
- Use SLF4J with parameterised messages; never log secrets or personal data.
- Tests: JUnit 5 with Mockito for units; slice tests (`@WebMvcTest`, `@DataJpaTest`) before full `@SpringBootTest`; Testcontainers only if already used.
- Run before finishing: `./mvnw test` (or `./gradlew test`) for touched modules, plus configured static checks (Checkstyle/SpotBugs).
