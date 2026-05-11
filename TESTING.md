# Test scenarios

## hello

**Tests:**
- Prints `Hello, World!` via `dotnet run`

```bash
docker compose build
docker compose -f docker-compose.yml -f docker-compose.hello.yml run --rm sandbox dotnet run
```

## docker-dotnet

**Prerequisites:** Docker socket mounted (base compose).

**Tests:**
- `DockerClient.PingAsync` succeeds over `/var/run/docker.sock`
- `docker info` CLI exits 0 and returns server version

```bash
docker compose build
docker compose -f docker-compose.yml -f docker-compose.docker-dotnet.yml run --rm sandbox \
  dotnet test /home/ubuntu/workspace
```

## dynamodb

**Prerequisites:** Docker socket; iptables DNAT port 8000 (`HOST_DOCKER_DNAT_PORTS=8000` set by overlay).

**Tests:**
- Pulls and starts `amazon/dynamodb-local:3.0.0` via Docker socket
- DNAT redirects `127.0.0.1:8000` inside container → `host.docker.internal:8000` on host

```bash
docker compose build
docker compose -f docker-compose.yml -f docker-compose.dynamodb.yml run --rm sandbox \
  dotnet test /home/ubuntu/workspace
```

## inbound-http

**Tests:**
- Minimal ASP.NET Core server binds `0.0.0.0:2002` inside the sandbox; port 2002 is published to the host
- A standalone `docker run` caller (outside the compose project) sends `GET http://host.docker.internal:2002/` (retrying until the server is ready)
- Server responds with `OK` and exits 0

```bash
docker compose build

# 1. Start the sandbox in the background
docker compose -f docker-compose.yml -f docker-compose.inbound-http.yml up -d

# 2. Run the caller as a standalone container (outside the compose project)
# --add-host is required on Linux for host.docker.internal to resolve
docker run --rm --add-host host.docker.internal:host-gateway curlimages/curl:latest \
  curl --fail --retry 30 --retry-delay 1 --retry-connrefused \
  http://host.docker.internal:2002/

# 3. Wait for the sandbox to exit and capture its exit code
docker compose -f docker-compose.yml -f docker-compose.inbound-http.yml wait sandbox
```

## log-file

**Tests:**
- Application runs inside the container and writes a timestamped log entry to `/var/log/app/app.log`
- `/var/log/app` is a bind-mounted host directory (`./testing/log-file/app-logs`), so the log file is readable on the host after the run

```bash
docker compose build
docker compose -f docker-compose.yml -f docker-compose.log-file.yml run --rm sandbox dotnet run

# Verify the log file was written to the host-mounted directory
cat ./testing/log-file/app-logs/app.log
```
