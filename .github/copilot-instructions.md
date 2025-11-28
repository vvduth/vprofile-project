# VProfile Project - AI Coding Agent Instructions

## Project Overview
VProfile is a multi-tier Java web application demonstrating containerization of a Spring MVC stack. The project showcases migrating from VM-based deployment to Docker containers with a service-oriented architecture.

**Tech Stack:** Spring MVC 6.0.11 + Spring Security 6.1.2 + Hibernate 7.0 + MySQL 8.0.33 + Memcached + RabbitMQ + Elasticsearch + Tomcat 10 + Nginx

## Architecture: Multi-Container Service Mesh

**5-Container Setup** (defined in `compose.yaml`):
- `duke-web` (nginx:latest) → Reverse proxy on port 80 → routes to `duke-app:8080`
- `duke-app` (tomcat:10-jdk21) → Spring MVC application 
- `duke-database` (mysql:8.0.33) → Persistent data store with health checks
- `vprocache01` (memcached) → Session/data caching on port 11211
- `vpromq01` (rabbitmq) → Message broker on ports 5672/15672

**Critical Service Dependencies:**
- All container names in `compose.yaml` MUST match `application.properties` (e.g., `duke-database`, `vprocache01`, `vpromq01`)
- Database connection string: `jdbc:mysql://duke-database:3306/accounts`
- Services communicate via Docker network bridge `vprofile-network`

## Build & Run Workflows

### Local Development
```bash
# Build Maven project (JDK 17 required)
mvn clean install -DskipTests

# Run tests
mvn test                    # Unit tests
mvn verify -DskipUnitTests  # Integration tests
```

### Docker Operations
```bash
# Build all images (run from project root)
docker compose build

# Start stack (database initializes with db_backup.sql)
docker compose up -d

# View logs for debugging
docker compose logs -f duke-app

# Access app: http://localhost (default credentials: admin_vp/admin_vp)

# Clean up
docker compose down
docker volume rm vprofile-project_duke-database-data vprofile-project_duke-app-data
```

## Dockerfile Patterns

### Multi-Stage Build Strategy (`Docker-files/app/app.Dockerfile`)
**Critical:** Uses 2-stage build to minimize image size
- **BUILD_IMAGE stage:** Uses `maven:3.9.9-eclipse-temurin-21-jammy` for compilation
- **Runtime stage:** Only `tomcat:10-jdk21` + WAR file
- Copies source from `../../` (relative to Dockerfile) → `/vprofile-project`
- Builds `vprofile-v2.war` → deploys as `ROOT.war` to Tomcat webapps

### Database Initialization (`Docker-files/db/db.Dockerfile`)
- Copies `db_backup.sql` to `docker-entrypoint-initdb.d/` for auto-execution on first startup
- Sets `MYSQL_ROOT_PASSWORD=dukepassword` and `MYSQL_DATABASE=accounts` (matches `application.properties`)

### Nginx Proxy (`Docker-files/web/web.Dockerfile`)
- Custom config at `nginxduke.conf` defines upstream `duke-app:8080`
- Simple reverse proxy: port 80 → Tomcat port 8080

## Spring Configuration Architecture

**XML-based config** (not annotation-driven):
- `appconfig-root.xml` → Imports mvc/data/rabbitmq/security configs
- `appconfig-data.xml` → JPA + Hibernate + MySQL datasource
- `appconfig-rabbitmq.xml` → RabbitMQ connection factory
- `appconfig-security.xml` → Spring Security rules

**Component Scanning:** Base package `com.visualpathit.account.*` scans for `@Service`, `@Controller`, `@Repository`

**Key Services:**
- `MemcachedUtils` → Caching layer (connects to `vprocache01:11211`)
- `RabbitMqUtil` → Message queue producer/consumer
- `ElasticsearchUtil` → Search indexing (configured but not containerized)
- `UserServiceImpl` → User management + Spring Security integration

## Configuration Anti-Patterns to Avoid

**Do NOT:**
- Change container names without updating `application.properties` (causes connection failures)
- Use `localhost` in JDBC URLs when containerized (use service names)
- Skip `depends_on` with `condition: service_healthy` for database (app fails before DB ready)
- Remove health checks from `duke-database` service
- Modify port mappings without updating Nginx upstream config

## Project-Specific Conventions

### Port Assignments
- **3308:3306** → MySQL (host:container) - Note non-standard host port 3308
- **8080:8080** → Tomcat application
- **80:80** → Nginx web server
- **11211:11211** → Memcached
- **5672/15672** → RabbitMQ (AMQP/Management)

### File Locations
- Source code: `src/main/java/com/visualpathit/account/`
- JSP views: `src/main/webapp/WEB-INF/views/`
- Database schema: `src/main/resources/db_backup.sql` (also copied to `Docker-files/db/`)
- Application config: `src/main/resources/application.properties`

### Volume Persistence
- `duke-database-data` → MySQL data at `/var/lib/mysql`
- `duke-app-data` → Tomcat webapps (allows hot WAR deployments)

## CI/CD Integration (Jenkinsfile)

Pipeline stages: BUILD → UNIT TEST → INTEGRATION TEST → CHECKSTYLE → SONARQUBE → NEXUS
- Uses Maven 3 for builds
- SonarQube analysis targets `src/` with JaCoCo coverage
- Artifacts published to Nexus with build ID versioning

## Common Debugging Scenarios

**App fails to start:** Check `docker compose logs duke-app` for:
- Database connection errors → Verify `duke-database` is healthy
- ClassNotFoundExceptions → Rebuild with `mvn clean install`

**404 on localhost:** Ensure WAR deployed as `ROOT.war` not `vprofile-v2.war` in Tomcat

**Network errors between services:** All services must be on `vprofile-network` bridge
