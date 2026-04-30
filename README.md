# sandbox

A sandboxed container environment with .NET 8, Node.js 22, and Python 3. All outbound traffic is routed through a mitmproxy firewall (`azure_firewall.py`) running on `127.0.0.1:8080`.

## Build

```bash
docker build -t sandbox .
```

## Run

```bash
docker run --rm -it sandbox
```

This starts an interactive bash shell inside the container with the mitmproxy firewall active.

### Mount a local workspace

```bash
docker run --rm -it -v "$(pwd)":/workspace sandbox
```

### Run a specific command

```bash
docker run --rm sandbox node --version
```

## Environment setup

Add your GitHub Copilot token to `~/.profile` so it's available in every session:

```bash
echo 'export COPILOT_GITHUB_TOKEN=<your-token>' >> ~/.profile
```

Then reload the profile or start a new shell:

```bash
source ~/.profile
```

Pass the token into the container at runtime:

```bash
docker run --rm -it -e COPILOT_GITHUB_TOKEN="$COPILOT_GITHUB_TOKEN" sandbox
```