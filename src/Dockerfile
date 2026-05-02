FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV DOTNET_NOLOGO=1

# Install system dependencies and .NET SDK via apt
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl wget git jq ca-certificates gnupg unzip bash openssh-client \
        python3 python3-pip python3-venv \
        dotnet-sdk-8.0 \
        iptables gosu \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g @github/copilot \
    && python3 -m venv /opt/mitmproxy \
    && /opt/mitmproxy/bin/pip install --no-cache-dir mitmproxy \
    && ln -s /opt/mitmproxy/bin/mitmdump /usr/local/bin/mitmdump \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI (client only — connects to host daemon via mounted socket)
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu noble stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update && apt-get install -y docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*


# Pre-generate mitmproxy CA and trust it system-wide (as root, at build time)
RUN HOME=/tmp/mitmproxy-setup mitmdump --version \
    && mkdir -p /home/ubuntu/.mitmproxy \
    && HOME=/home/ubuntu mitmdump -q &>/dev/null & sleep 2 && kill $! 2>/dev/null || true \
    && cp /home/ubuntu/.mitmproxy/mitmproxy-ca-cert.pem /usr/local/share/ca-certificates/mitmproxy.crt \
    && update-ca-certificates \
    && mkdir -p /etc/mitmproxy/certs \
    && cp /home/ubuntu/.mitmproxy/mitmproxy-ca*.pem /etc/mitmproxy/certs/ \
    && chmod 755 /etc/mitmproxy/certs \
    && chmod 644 /etc/mitmproxy/certs/mitmproxy-ca-cert.pem \
    && chmod 600 /etc/mitmproxy/certs/mitmproxy-ca.pem

# Copy entrypoint, copiloty wrapper, firewall rules, and set up workspace/mitmproxy directories with correct ownership
COPY entrypoint.sh /etc/mitmproxy/entrypoint.sh
COPY cop.sh /usr/local/bin/cop.sh
COPY firewall/ /etc/mitmproxy/config/
COPY skills/ /home/ubuntu/.copilot/skills/
RUN chmod +x /etc/mitmproxy/entrypoint.sh \
    && chmod +x /usr/local/bin/cop.sh \
    && ln -s /usr/local/bin/cop.sh /usr/local/bin/cop \
    && ln -s /usr/local/bin/cop.sh /usr/local/bin/copiloty \
    && mkdir -p /home/ubuntu/workspace /var/log/mitmproxy /etc/mitmproxy/config /etc/mitmproxy/user-rules \
    && chmod -R a+rx /etc/mitmproxy \
    && chown -R root:root /home/ubuntu \
    && chmod 755 /home/ubuntu \
    && mkdir -p /home/ubuntu/workspace /home/ubuntu/.copilot /home/ubuntu/.cache/copilot /home/ubuntu/.dotnet /home/ubuntu/.nuget/NuGet /home/ubuntu/.local/share /home/ubuntu/.local/share/NuGet \
    && chown ubuntu:ubuntu /home/ubuntu/workspace /home/ubuntu/.copilot /home/ubuntu/.cache /home/ubuntu/.cache/copilot /home/ubuntu/.dotnet /home/ubuntu/.nuget /home/ubuntu/.nuget/NuGet /home/ubuntu/.local /home/ubuntu/.local/share /home/ubuntu/.local/share/NuGet \
    && chmod 755 /home/ubuntu/workspace /home/ubuntu/.copilot /home/ubuntu/.cache /home/ubuntu/.cache/copilot /home/ubuntu/.dotnet /home/ubuntu/.nuget /home/ubuntu/.nuget/NuGet /home/ubuntu/.local /home/ubuntu/.local/share /home/ubuntu/.local/share/NuGet \
    && printf '// User settings belong in settings.json.\n// This file is managed automatically.\n{\n  "trustedFolders": ["/home/ubuntu/workspace"]\n}\n' \
        > /home/ubuntu/.copilot/config.json \
    && chown ubuntu:ubuntu /home/ubuntu/.copilot/config.json \
    && chmod 600 /home/ubuntu/.copilot/config.json \
    && chown root:root /home/ubuntu/.mitmproxy \
    && chmod 750 /home/ubuntu/.mitmproxy

ENV HTTP_PROXY=http://127.0.0.1:8080
ENV HTTPS_PROXY=http://127.0.0.1:8080
ENV ALL_PROXY=http://127.0.0.1:8080
ENV NO_PROXY=localhost,127.0.0.1

# Entrypoint runs as root to set iptables, then drops to ubuntu via gosu
WORKDIR /home/ubuntu/workspace

ENTRYPOINT ["/etc/mitmproxy/entrypoint.sh"]
CMD ["copiloty"]
