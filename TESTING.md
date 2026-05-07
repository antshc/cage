# Test scenarios

## hello

```bash
docker compose build
docker compose run --rm sandbox dotnet run
```

## docker-dotnet

Requires Docker socket (mounted in base compose).

```bash
docker compose build
docker compose -f docker-compose.yml -f docker-compose.docker-dotnet.yml run --rm sandbox \
  dotnet test /home/ubuntu/workspace --filter "Category=Integration"
```

## dynamodb

Requires Docker socket and iptables DNAT on port 8000 (`HOST_DOCKER_DNAT_PORTS=8000` set by overlay). The test starts `amazon/dynamodb-local` via the Docker socket; the DNAT rule redirects `127.0.0.1:8000` inside the container to `host.docker.internal:8000` on the host.

```bash
docker compose build
docker compose -f docker-compose.yml -f docker-compose.dynamodb.yml run --rm sandbox \
  dotnet test /home/ubuntu/workspace --filter "Category=Integration"
```
