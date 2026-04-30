FROM mcr.microsoft.com/dotnet/sdk:8.0

ENV DEBIAN_FRONTEND=noninteractive
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV DOTNET_NOLOGO=1

# Install system dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl wget git jq ca-certificates gnupg sudo unzip bash openssh-client \
        python3 python3-pip python3-venv \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g @github/copilot \
    && python3 -m venv /opt/mitmproxy \
    && /opt/mitmproxy/bin/pip install --no-cache-dir mitmproxy \
    && ln -s /opt/mitmproxy/bin/mitmdump /usr/local/bin/mitmdump \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Azure CLI
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Create the agent user with UID/GID 1000 for secure filesystem access.
# Using UID 1000 ensures --userns=keep-id (Podman) and --user 1000:1000 (Docker)
# map correctly to the home directory owner.
ARG USERNAME=agent
ARG USER_UID=1000
ARG USER_GID=1000

RUN groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m ${USERNAME} -s /bin/bash \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

# Copy entrypoint and set up workspace/mitmproxy directories with correct ownership
COPY entrypoint.sh /etc/mitmproxy/entrypoint.sh
RUN chmod +x /etc/mitmproxy/entrypoint.sh \
    && mkdir -p /home/${USERNAME}/workspace /var/log/mitmproxy /etc/mitmproxy \
    && chmod -R a+rx /etc/mitmproxy \
    && chown -R ${USERNAME}:${USERNAME} /home/${USERNAME} /etc/mitmproxy /var/log/mitmproxy

ENV HTTP_PROXY=http://127.0.0.1:8080
ENV HTTPS_PROXY=http://127.0.0.1:8080
ENV ALL_PROXY=http://127.0.0.1:8080
ENV NO_PROXY=localhost,127.0.0.1

# Switch to agent user for secure sandboxed execution
USER ${USERNAME}

# In worktree sandbox mode, the git worktree is bind-mounted at /home/agent/workspace
# and overrides the working directory at container start.
WORKDIR /home/${USERNAME}/workspace

ENTRYPOINT ["/etc/mitmproxy/entrypoint.sh"]
CMD ["/bin/bash"]