# Containerizing a Multi-Tier Java Application with Docker

## Understanding the Problem

Let's start by understanding the scenario. Imagine you have a multi-tier application stack with many services that you manage as an operations or DevOps team. These services are running on VMs in a VMware environment, on cloud instances like EC2, or on physical machines in your own data center.

In today's world, we need to do continuous deployment for constant changes. This brings several challenges:

### The Cost Problem

First, we have to spend a lot of money. Whether you procure physical resources or use cloud platforms, there are significant costs. But it's not just about spending money. Are we really using all those resources? If you're running an application service with 10 GB of RAM, is it really using all 10 GB? If you take an average over an entire year, you will find significant resource wastage, and that wastage is very expensive.

### The Consistency Problem

When we do deployments, there are always chances of making human errors. Automation can help, but you often have different environments (dev, staging, production) with different versions that are not in sync. This makes it difficult to maintain consistency across environments.

### The Microservices Challenge

Today's architecture trend is microservices. If you want to implement microservices on operating systems running directly on virtual machines, you will end up spending a lot of money because microservices have multiple substacks in a stack. The point is, we are not using all those resources. Mostly, there will be resource wastage.

## Why Containers Are the Solution

Containers are the solution we are looking for. If you can containerize an application, you can save a lot of money because containers use far fewer resources. There are no full operating systems in containers, so they use fewer resources. This makes them very suitable for microservice architecture.

### Benefits of Containerization

With containers, deployments are done via images. If you package your images properly with all the dependencies, binaries, and libraries necessary, then if it works on your laptop, it will work in a QA environment. The same container image will work in production because we have the same container image across all environments. This makes our stack reusable and repeatable.

## The Project: Containerizing a Java Application Stack

In this project, we are going to use Docker as our container runtime environment to build images. We are containerizing a Java application stack with multiple services:

- **Nginx** (Web server / Reverse proxy)
- **Tomcat** (Application server)
- **MySQL** (Database)
- **Memcached** (Caching layer)
- **RabbitMQ** (Message broker)

An important point: **you do not need deep knowledge of all these services to containerize them**. You also do not need to read and understand every single line of code if your job is just to dockerize and containerize them. Later on, I will containerize more applications and services that I do not know much about, to prove that you do not need to be an expert in all these services to containerize them.

### Tools We Will Use

We are not going to just use the Docker engine. We will use:

- **Docker** - Container runtime to build and run images
- **Docker Compose** - To orchestrate multiple containers
- **Docker Hub** - To host our images

### The Containerization Workflow

Here's our approach:

1. **Find the right base images** from Docker Hub for all the services (Nginx, Tomcat, MySQL, Memcached, RabbitMQ)
2. **Write Dockerfiles** for the services that need customization (Nginx needs our configuration, MySQL needs our data and schema)
3. **Build the images** from the Dockerfiles
4. **Write a Docker Compose file** to launch all these containers together
5. **Test the multi-container environment**
6. **Push our images to Docker Hub** if everything checks out

Let's get started.

## Step 0: Identifying Service Versions

First, we need to identify the base images and versions for all services. Normally, the developer will give you this information:

| Service | Version | Docker Image |
|---------|---------|--------------|
| MySQL (Database) | 8.0.33 | `mysql:8.0.33` |
| Memcached (Caching) | latest | `memcached:latest` |
| RabbitMQ (Message Broker) | latest | `rabbitmq:latest` |
| Maven (Build Tool) | 3.9.9 | `maven:3.9.9-eclipse-temurin-21-jammy` |
| JDK (Java Runtime) | 21 | Included in Maven and Tomcat images |
| Tomcat (Application Server) | 10 with JDK 21 | `tomcat:10-jdk21` |
| Nginx (Web Server) | latest | `nginx:latest` |

## Step 1: Dockerfile for the Application (Tomcat)

The application Dockerfile is located at `Docker-files/app/app.Dockerfile`. This uses a **multi-stage build** pattern:

```dockerfile
FROM maven:3.9.9-eclipse-temurin-21-jammy AS BUILD_IMAGE

# Copy local source code instead of cloning
COPY ../../ /vprofile-project
WORKDIR /vprofile-project
RUN mvn clean install -DskipTests

FROM tomcat:10-jdk21

RUN rm -rf /usr/local/tomcat/webapps/*

COPY --from=BUILD_IMAGE vprofile-project/target/vprofile-v2.war /usr/local/tomcat/webapps/ROOT.war

EXPOSE 8080
CMD ["catalina.sh", "run"]
```

### Why Use Multi-Stage Build?

The build stage has a lot of dependencies: Maven, Git, JDK, and all the build tools. But the runtime stage only needs Tomcat and JDK. We could use just one stage, but the image size would be very large.

By separating the build stage and runtime stage, we get a much smaller image size for runtime. This is important for:

- **Faster deployments** - Smaller images transfer faster
- **Less storage** - Saves space in registries and on servers
- **Better security** - Fewer tools in production means fewer attack vectors

### How It Works

1. **BUILD_IMAGE stage** - Uses the Maven image to compile the Java application and create a WAR file
2. **Runtime stage** - Uses the Tomcat image and copies only the WAR file from the build stage
3. **Clean webapps** - Removes default Tomcat webapps to ensure our app is the only one running
4. **Deploy as ROOT** - Copies our WAR as `ROOT.war` so the app is accessible at `http://localhost/` instead of `http://localhost/vprofile-v2/`

## Step 2: Dockerfile for MySQL

The MySQL Dockerfile is located at `Docker-files/db/db.Dockerfile`. Here's what we need to do:

1. Set up username, password, and database name
2. Initialize the database using the SQL dump file located at `src/main/resources/db/db_backup.sql`

```dockerfile
FROM mysql:8.0.33
LABEL "Project"="duke-database"
LABEL "author"="duke"

# Get these values from application.properties file
ENV MYSQL_PASSWORD="dukepassword"
ENV MYSQL_DATABASE="accounts"

# Copy the database backup file to the docker entrypoint init db folder
# According to MySQL Docker docs, all .sql files in this folder 
# will be executed during container startup
ADD db_backup.sql docker-entrypoint-initdb.d/db_backup.sql
```

### How MySQL Initialization Works

The MySQL Docker image has a special feature: any `.sql` files placed in the `/docker-entrypoint-initdb.d/` directory will be automatically executed when the container starts for the first time. This is perfect for:

- Creating database schemas
- Populating initial data
- Setting up user permissions

In our case, we copy `db_backup.sql` which contains all the table definitions and initial data for the application.

## Step 3: Dockerfile for Nginx

The Nginx Dockerfile is pretty simple. We install the service and add our custom configuration file. Our configuration says: if a request comes on port 80 (the default HTTP port), forward it to Tomcat on port 8080.

You can connect the config as a volume, or you can copy the configuration directly into your image and then build the image. In our case, our configuration is straightforward, so we just copy it directly.

### Nginx Configuration File

Here is our Nginx config at `Docker-files/web/nginxduke.conf`:

```nginx
# Make sure the Tomcat container name is correct and matches
events {
    worker_connections 1024;
}

http {
  upstream duke-app {
    server duke-app:8080;
  }
  
  server {
    listen 80;
    location / {
      proxy_pass http://duke-app;
    }
  }
}
```

**Important:** The upstream server name `duke-app` must match the container name of the Tomcat service in Docker Compose. This is how Docker's internal DNS resolution works.

### Nginx Dockerfile

```dockerfile
FROM nginx
LABEL "Project"="duke-web"
LABEL "author"="duke"

# Remove the default nginx config file
# RUN rm -rf /etc/nginx/nginx.conf

# Copy our custom nginx config file
COPY nginxduke.conf /etc/nginx/nginx.conf
```

This Dockerfile simply takes the base Nginx image and replaces the default configuration with our custom one.

## Step 4: Memcached and RabbitMQ

For these two services, we do not need any customization. They will work fine with their default configurations. So we do not need to write any Dockerfile for them. We just state the base image in the Docker Compose file.

This is one of the great benefits of Docker: many services can run out-of-the-box without any customization.

## Step 5: Docker Compose File to Run Multi-Container Application

Now we bring everything together with Docker Compose. In total, we have **5 containers**:

1. **duke-app** (Tomcat)
   - Uses our custom Dockerfile
   - Port: `8080:8080`
   - Volume: `/usr/local/tomcat/webapps` (we can also use this volume to mount the WAR file from the host if we don't want to rebuild the image every time we have a new WAR file)

2. **duke-database** (MySQL)
   - Container name must be `duke-database` (as specified in `application.properties`)
   - Uses our custom Dockerfile
   - Port: `3308:3306` (host port 3308 maps to container port 3306)
   - Environment: `MYSQL_ROOT_PASSWORD=dukepassword`
   - Volume: `/var/lib/mysql` (we need this volume to persist the data)

3. **duke-web** (Nginx)
   - Uses our custom Dockerfile
   - Port: `80:80`

4. **vprocache01** (Memcached)
   - Uses Docker Hub base image
   - Container name must be `vprocache01` (as specified in `application.properties`)
   - Port: `11211:11211`

5. **vpromq01** (RabbitMQ)
   - Uses Docker Hub base image
   - Container name must be `vpromq01` (as specified in `application.properties`)
   - Ports: `5672:5672` (AMQP) and `15672:15672` (Management UI)
   - Environment: `RABBITMQ_DEFAULT_USER=guest`, `RABBITMQ_DEFAULT_PASS=guest`

### The Complete Docker Compose File

Here is our `compose.yaml` file:

```yaml
services:
   duke-database:
    build:
      context: ./Docker-files/db
      dockerfile: db.Dockerfile
    image: vvduth/dukeapp-db
    container_name: duke-database
    ports: 
      - "3308:3306"
    volumes:
      - duke-database-data:/var/lib/mysql
    environment:
      - MYSQL_ROOT_PASSWORD=dukepassword
      - MYSQL_DATABASE=accounts
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-uroot", "-pdukepassword"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - vprofile-network

   vprocache01:
    image: memcached
    container_name: vprocache01
    ports:
      - "11211:11211"
    networks:
      - vprofile-network

   vpromq01:
    image: rabbitmq
    container_name: vpromq01
    ports:
      - "15672:15672"
      - "5672:5672"
    environment:
      - RABBITMQ_DEFAULT_USER=guest
      - RABBITMQ_DEFAULT_PASS=guest
    networks:
      - vprofile-network

   duke-app:
    build:
      context: ../vprofile-project
      dockerfile: Docker-files/app/app.Dockerfile
    image: vvduth/dukeapp-server
    container_name: duke-app
    ports:
      - "8080:8080"
    volumes:
      - duke-app-data:/usr/local/tomcat/webapps
    depends_on:
      duke-database:
        condition: service_healthy
    networks:
      - vprofile-network
    restart: on-failure:5
    
volumes:
  duke-database-data: {}
  duke-app-data: {}

networks:
  vprofile-network:
    driver: bridge
```

### Understanding the Docker Compose Configuration

**Health Checks:** I added health checks for the database during the debugging process. The `duke-app` service depends on `duke-database` with the condition `service_healthy`, which means Docker Compose will wait for the database to be fully ready before starting the application container. This prevents connection errors during startup.

**Networks:** All services are on the same custom bridge network `vprofile-network`. This allows containers to communicate with each other using their container names as hostnames.

**Volumes:** We define two volumes for data persistence:
- `duke-database-data` - Stores MySQL data so we don't lose our database when containers are stopped
- `duke-app-data` - Stores Tomcat webapps for potential hot deployments

**Restart Policy:** The `duke-app` service has `restart: on-failure:5`, which means Docker will automatically restart the container up to 5 times if it fails.

## Building and Running the Application

Now that we have all our Dockerfiles and Docker Compose configuration ready, let's build and run our multi-container application.

### Step 1: Build All Images

Run this command from the project root directory:

```bash
docker compose build
```

This command will build all the custom images defined in our Docker Compose file. After everything is done, run `docker images` to see all the images:

```
REPOSITORY              TAG       IMAGE ID       CREATED              SIZE
vvduth/dukeapp-server   latest    502774e5bb7f   56 seconds ago       878MB
vvduth/dukeapp-web      latest    e0ebd5b8d3c8   About a minute ago   225MB
vvduth/dukeapp-db       latest    a779086eba0e   2 minutes ago        772MB
```

### Step 2: Start All Containers

To run all containers in detached mode (in the background):

```bash
docker compose up -d
```

If you want to see the logs in real-time (useful for debugging):

```bash
docker compose up
```

### Step 3: Verify the Application

You should be able to see all containers are up and running. When you visit `http://localhost`, you should see the application running fine.

**Login credentials:**
- Username: `admin_vp`
- Password: `admin_vp`

## Pushing Images to Docker Hub

Once you have tested your application and everything works correctly, you can push your images to Docker Hub so others can use them or you can deploy them to other environments.

### Step 1: Login to Docker Hub

```bash
docker login
```

Enter your Docker Hub credentials when prompted.

### Step 2: Tag Your Images (if needed)

If your images don't already have the correct tag with your Docker Hub ID, tag them:

```bash
docker tag dukeapp-server:latest yourusername/dukeapp-server:latest
docker tag dukeapp-web:latest yourusername/dukeapp-web:latest
docker tag dukeapp-db:latest yourusername/dukeapp-db:latest
```

### Step 3: Push Images to Docker Hub

```bash
docker push yourusername/dukeapp-server:latest
docker push yourusername/dukeapp-web:latest
docker push yourusername/dukeapp-db:latest
```

## Cleaning Up Your Docker Environment

When you're done testing or want to clean up resources:

### Stop and Remove All Containers

```bash
docker compose down
```

### Remove Images

```bash
docker rmi vvduth/dukeapp-server vvduth/dukeapp-web vvduth/dukeapp-db
```

### Remove Volumes

To remove the volumes (this will delete all database data):

```bash
docker volume rm vprofile-project_duke-database-data vprofile-project_duke-app-data
```

### Remove All Unused Data

For a complete cleanup of all unused Docker resources:

```bash
docker system prune -a
```

**Warning:** This command will remove all unused images, containers, networks, and optionally volumes. Use with caution.

## Key Takeaways

In this project, we successfully containerized a complex multi-tier Java application with five different services. Here are the key lessons:

1. **You don't need to be an expert** in every technology to containerize it. Understanding the basic requirements and configuration is enough.

2. **Multi-stage builds** are crucial for keeping production images small and secure.

3. **Container naming matters** - Make sure container names in Docker Compose match what your application expects in configuration files.

4. **Health checks and dependencies** ensure services start in the correct order and are ready before dependent services try to connect.

5. **Docker Compose** makes managing multi-container applications simple and repeatable.

6. **Volumes** are essential for data persistence and can also be used for hot deployments during development.

This containerization approach gives us:
- **Consistency** across all environments
- **Resource efficiency** compared to VMs
- **Easy deployment** and scaling
- **Reproducibility** - if it works on your laptop, it works in production

The same principles can be applied to containerize almost any multi-tier application, regardless of the specific technologies involved.