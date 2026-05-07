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
