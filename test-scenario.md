# Test scenario: DynamoDB via iptables DNAT

Demonstrates iptables OUTPUT DNAT inside the sandbox container. `DynamoDbConnectivityTests`
connects to `127.0.0.1:8000`; the sandbox entrypoint redirects those packets to
`host.docker.internal:8000`, which the test's own Docker-managed DynamoDB container is bound to.

```
[sandbox container]  NET_ADMIN + route_localnet
  DynamoDbConnectivityTests → http://127.0.0.1:8000
        │
        │  iptables OUTPUT DNAT (inside sandbox netns)
        │  127.0.0.1:8000 → host.docker.internal:8000
        ▼
[Docker host]  port 8000
        ▼
[amazon/dynamodb-local]  started by the test via /var/run/docker.sock → "Hello DynamoDB"
```

---

## 1. Build the sandbox image

```bash
docker build -t sandbox ./src
```

## 2. Run the tests

```bash
docker run --rm \
  --cap-add NET_ADMIN \
  --cap-add SETUID \
  --cap-add SETGID \
  --cap-drop ALL \
  --sysctl net.ipv4.conf.all.route_localnet=1 \
  --add-host host.docker.internal:host-gateway \
  -e COPILOT_GITHUB_TOKEN="${COPILOT_GITHUB_TOKEN}" \
  -e HOST_DOCKER_DNAT_PORTS=8000 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$(pwd)/workspace":/home/ubuntu/workspace \
  -v "$(pwd)/logs/mitmproxy":/var/log/mitmproxy \
  -v "$(pwd)/logs/copilot":/var/log/copilot \
  sandbox \
  dotnet test /home/ubuntu/workspace/DockerConnectivity.Tests/ \
    --filter "Category=Integration" \
    --logger "console;verbosity=normal"
```

### What happens on startup

The entrypoint runs as root and installs this iptables rule before dropping to `ubuntu`:

```
iptables -t nat -A OUTPUT -p tcp -d 127.0.0.1 --dport 8000 \
  -j DNAT --to-destination <host-gateway>:8000
```

This rule is now driven by `HOST_DOCKER_DNAT_PORTS=8000` passed to the container.
See README for the full format (multiple ports, ranges).

`DynamoDbConnectivityTests` then:
1. Connects to the Docker socket and starts a `amazon/dynamodb-local:3.0.0` container
   bound to host port `8000`.
2. Issues `ListTablesAsync()` against `http://127.0.0.1:8000` — transparently redirected
   to the DynamoDB container via the DNAT rule.
3. Stops and removes the DynamoDB container in `DisposeAsync`.

## 3. Verify the DNAT rule (optional)

Inspect the iptables nat OUTPUT chain from inside the container:

```bash
docker run --rm \
  --cap-add NET_ADMIN \
  --cap-add SETUID \
  --cap-add SETGID \
  --cap-drop ALL \
  --sysctl net.ipv4.conf.all.route_localnet=1 \
  --add-host host.docker.internal:host-gateway \
  -e COPILOT_GITHUB_TOKEN="${COPILOT_GITHUB_TOKEN}" \
  -v "$(pwd)/logs/mitmproxy":/var/log/mitmproxy \
  -v "$(pwd)/logs/copilot":/var/log/copilot \
  sandbox \
  bash -c "iptables -t nat -L OUTPUT -n -v"
```

Expected output includes:

```
DNAT  tcp  --  *  *  0.0.0.0/0  127.0.0.1  tcp dpt:8000 to:<host-gateway>:8000
```
