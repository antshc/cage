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


# Copy entrypoint and set up workspace/mitmproxy directories with correct ownership
COPY entrypoint.sh /etc/mitmproxy/entrypoint.sh
RUN chmod +x /etc/mitmproxy/entrypoint.sh \
    && mkdir -p /home/ubuntu/workspace /var/log/mitmproxy /etc/mitmproxy/config \
    && chmod -R a+rx /etc/mitmproxy \
    && chown -R ubuntu:ubuntu /home/ubuntu /etc/mitmproxy /var/log/mitmproxy \
       /usr/local/share/ca-certificates /etc/ssl/certs

ENV HTTP_PROXY=http://127.0.0.1:8080
ENV HTTPS_PROXY=http://127.0.0.1:8080
ENV ALL_PROXY=http://127.0.0.1:8080
ENV NO_PROXY=localhost,127.0.0.1

# Switch to ubuntu user for secure sandboxed execution
USER ubuntu

# In worktree sandbox mode, the git worktree is bind-mounted at /home/ubuntu/workspace
# and overrides the working directory at container start.
WORKDIR /home/ubuntu/workspace

ENTRYPOINT ["/etc/mitmproxy/entrypoint.sh"]
CMD ["/bin/bash"]