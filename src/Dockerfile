ARG UBUNTU_VERSION=24.04

FROM ubuntu:${UBUNTU_VERSION}

ARG UBUNTU_CODENAME=noble
ARG NODE_MAJOR=24
ARG DOTNET_VERSION=8.0.411

ENV DEBIAN_FRONTEND=noninteractive
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV DOTNET_NOLOGO=1

# Install base packages, add all third-party repos, then install repo packages — single update/clean cycle
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl wget git jq ca-certificates gnupg unzip bash openssh-client \
        iproute2 net-tools lsof netcat-openbsd \
        python3 python3-pip python3-venv \
        libicu74 libssl3t64 \
        iptables gosu iputils-ping \
    # Node 22 repo
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
        > /etc/apt/sources.list.d/nodesource.list \
    # GitHub CLI repo
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    # Docker CLI repo (client only — connects to host daemon via mounted socket)
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable" \
        | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    # Refresh index once for all new repos, then install
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs gh docker-ce-cli \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install .NET SDK 8.0.411 via the official dotnet-install script
# (apt repos for Ubuntu 24.04 only carry 8.0.1xx; exact feature-band versions require the script)
RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
    && chmod +x /tmp/dotnet-install.sh \
    && /tmp/dotnet-install.sh --version ${DOTNET_VERSION} --install-dir /usr/share/dotnet \
    && ln -s /usr/share/dotnet/dotnet /usr/local/bin/dotnet \
    && rm /tmp/dotnet-install.sh \
    && curl -fsSL https://gh.io/copilot-install | bash \
    && python3 -m venv /opt/mitmproxy \
    && /opt/mitmproxy/bin/pip install --no-cache-dir mitmproxy \
    && ln -s /opt/mitmproxy/bin/mitmdump /usr/local/bin/mitmdump

# Create private global Python venv for ubuntu user (mirrors antshc/python-env convention)
RUN mkdir -p /home/ubuntu/.venvs \
    && python3 -m venv /home/ubuntu/.venvs/global \
    && /home/ubuntu/.venvs/global/bin/python -m pip install --upgrade --no-cache-dir pip setuptools wheel pipx \
    && chown -R ubuntu:ubuntu /home/ubuntu/.venvs


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
COPY copilot-alias.sh /usr/local/bin/copilot-alias.sh
COPY firewall/ /etc/mitmproxy/config/
COPY skills/ /home/ubuntu/.copilot/skills/
RUN chmod +x /etc/mitmproxy/entrypoint.sh \
    && chmod +x /usr/local/bin/copilot-alias.sh \
    && ln -s /usr/local/bin/copilot-alias.sh /usr/local/bin/copiloty \
    && mkdir -p /home/ubuntu/workspace /var/log/mitmproxy /var/log/copilot /etc/mitmproxy/config /etc/mitmproxy/user-rules \
    && chown -R ubuntu:ubuntu /var/log \
    && chmod -R a+rx /etc/mitmproxy \
    && chown -R ubuntu:ubuntu /home/ubuntu \
    && chmod 755 /home/ubuntu \
    && printf '// User settings belong in settings.json.\n// This file is managed automatically.\n{\n  "trustedFolders": ["/home/ubuntu/workspace"]\n}\n' \
        > /home/ubuntu/.copilot/config.json \
    && chown ubuntu:ubuntu /home/ubuntu/.copilot/config.json \
    && chmod 600 /home/ubuntu/.copilot/config.json \
    && chown root:root /home/ubuntu/.mitmproxy \
    && chmod 750 /home/ubuntu/.mitmproxy

ENV HTTP_PROXY=http://127.0.0.1:18080
ENV HTTPS_PROXY=http://127.0.0.1:18080
ENV ALL_PROXY=http://127.0.0.1:18080
ENV NO_PROXY=localhost,127.0.0.1
ENV DOTNET_ROOT=/usr/share/dotnet
ENV PATH=/home/ubuntu/.local/bin:/home/ubuntu/.venvs/global/bin:$PATH
ENV PIPX_HOME=/home/ubuntu/.local/pipx
ENV PIPX_BIN_DIR=/home/ubuntu/.local/bin

# Entrypoint runs as root to set iptables, then drops to ubuntu via gosu
WORKDIR /home/ubuntu/workspace

ENTRYPOINT ["/etc/mitmproxy/entrypoint.sh"]
CMD ["copiloty"]
