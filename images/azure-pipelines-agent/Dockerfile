# syntax=docker/dockerfile:1.19
FROM ubuntu:24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90

ARG AZP_AGENT_VERSION=3.238.0
ARG DOTNET_10_SDK_VERSION=10.0.302
ARG DOTNET_8_SDK_VERSION=8.0.423
ARG DOTNET_INSTALL_COMMIT=cfd77e68a4adb8d4077601b88ce6a304efb4ba72
ARG SONAR_SCANNER_CLI_VERSION=8.1.0.6389
ARG SONAR_SCANNER_CLI_SHA256=bb8f709f9cb73352f8d1260a3b3c506c0f41146754bc630762c126d795499d0b
ARG SONAR_SCANNER_DOTNET_VERSION=11.2.1
ARG UV_VERSION=0.12.0
ARG POWERSHELL_VERSION=7.6.4
ARG CMAKE_VERSION=4.4.1
ARG NINJA_VERSION=1.13.2
ARG KUBECTL_VERSION=1.36.2
ARG HELM_VERSION=4.2.3
ARG KUSTOMIZE_VERSION=5.8.1
ARG YQ_VERSION=4.53.3
ARG OPENTOFU_VERSION=1.12.5
ARG TRIVY_VERSION=0.72.0
ARG COSIGN_VERSION=3.1.2
ARG SYFT_VERSION=1.50.0
ARG GRYPE_VERSION=0.116.1
ARG ORAS_VERSION=1.3.3

LABEL org.opencontainers.image.title="ASOL Azure Pipelines Linux Agent" \
      org.opencontainers.image.description="Azure DevOps Server 2022.2 compatible CI and SonarQube toolbox" \
      io.asol.azure-pipelines-agent.version="${AZP_AGENT_VERSION}" \
      io.asol.sonar-scanner-cli.version="${SONAR_SCANNER_CLI_VERSION}" \
      io.asol.sonar-scanner-dotnet.version="${SONAR_SCANNER_DOTNET_VERSION}" \
      io.asol.uv.version="${UV_VERSION}"

ENV DEBIAN_FRONTEND=noninteractive \
    DOTNET_ROOT=/usr/share/dotnet \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 \
    UV_PYTHON_DOWNLOADS=automatic \
    PATH=/opt/dotnet-tools:/usr/share/dotnet:/opt/sonar-scanner/bin:/opt/powershell:/usr/local/bin:/usr/bin:/bin

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      ccache \
      clang \
      clang-tidy \
      cppcheck \
      curl \
      file \
      gdb \
      git \
      git-lfs \
      gnupg \
      jq \
      libicu74 \
      libssl3 \
      libunwind8 \
      lcov \
      openjdk-21-jdk-headless \
      passwd \
      pkg-config \
      shellcheck \
      skopeo \
      tar \
      unzip \
      xz-utils \
      zip \
      zlib1g; \
    rm -rf /var/lib/apt/lists/*; \
    git lfs install --system

RUN set -eux; \
    curl -fsSL "https://raw.githubusercontent.com/dotnet/install-scripts/${DOTNET_INSTALL_COMMIT}/src/dotnet-install.sh" -o /usr/local/bin/dotnet-install; \
    chmod 0755 /usr/local/bin/dotnet-install; \
    /usr/local/bin/dotnet-install --version "${DOTNET_10_SDK_VERSION}" --install-dir "${DOTNET_ROOT}" --no-path; \
    /usr/local/bin/dotnet-install --version "${DOTNET_8_SDK_VERSION}" --install-dir "${DOTNET_ROOT}" --no-path; \
    ln -s "${DOTNET_ROOT}/dotnet" /usr/local/bin/dotnet; \
    mkdir -p /opt/dotnet-tools; \
    dotnet tool install dotnet-sonarscanner --tool-path /opt/dotnet-tools --version "${SONAR_SCANNER_DOTNET_VERSION}"

RUN set -eux; \
    mkdir -p /tmp/tooling /opt/sonar-scanner /opt/powershell; \
    curl -fsSL "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_CLI_VERSION}-linux-x64.zip" -o /tmp/tooling/sonar-scanner.zip; \
    echo "${SONAR_SCANNER_CLI_SHA256}  /tmp/tooling/sonar-scanner.zip" | sha256sum -c -; \
    unzip -q /tmp/tooling/sonar-scanner.zip -d /tmp/tooling/sonar; \
    cp -a "/tmp/tooling/sonar/sonar-scanner-${SONAR_SCANNER_CLI_VERSION}-linux-x64/." /opt/sonar-scanner/; \
    curl -fsSL "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz" | tar -xz -C /tmp/tooling; \
    install -m 0755 /tmp/tooling/uv-x86_64-unknown-linux-gnu/uv /usr/local/bin/uv; \
    install -m 0755 /tmp/tooling/uv-x86_64-unknown-linux-gnu/uvx /usr/local/bin/uvx; \
    curl -fsSL "https://github.com/PowerShell/PowerShell/releases/download/v${POWERSHELL_VERSION}/powershell-${POWERSHELL_VERSION}-linux-x64.tar.gz" | tar -xz -C /opt/powershell; \
    chmod 0755 /opt/powershell/pwsh; \
    ln -s /opt/powershell/pwsh /usr/local/bin/pwsh; \
    curl -fsSL "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz" | tar -xz --strip-components=1 -C /usr/local; \
    curl -fsSL "https://github.com/ninja-build/ninja/releases/download/v${NINJA_VERSION}/ninja-linux.zip" -o /tmp/tooling/ninja.zip; \
    unzip -q /tmp/tooling/ninja.zip -d /tmp/tooling/ninja; \
    install -m 0755 /tmp/tooling/ninja/ninja /usr/local/bin/ninja; \
    rm -rf /tmp/tooling

RUN set -eux; \
    mkdir -p /tmp/platform-tools; \
    curl -fsSL "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl; \
    chmod 0755 /usr/local/bin/kubectl; \
    curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" | tar -xz -C /tmp/platform-tools; \
    install -m 0755 /tmp/platform-tools/linux-amd64/helm /usr/local/bin/helm; \
    curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" | tar -xz -C /usr/local/bin; \
    curl -fsSL "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64" -o /usr/local/bin/yq; \
    chmod 0755 /usr/local/bin/yq; \
    curl -fsSL "https://github.com/opentofu/opentofu/releases/download/v${OPENTOFU_VERSION}/tofu_${OPENTOFU_VERSION}_linux_amd64.zip" -o /tmp/platform-tools/tofu.zip; \
    unzip -q /tmp/platform-tools/tofu.zip -d /tmp/platform-tools/tofu; \
    install -m 0755 /tmp/platform-tools/tofu/tofu /usr/local/bin/tofu; \
    curl -fsSL "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" | tar -xz -C /tmp/platform-tools trivy; \
    install -m 0755 /tmp/platform-tools/trivy /usr/local/bin/trivy; \
    curl -fsSL "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-linux-amd64" -o /usr/local/bin/cosign; \
    chmod 0755 /usr/local/bin/cosign; \
    curl -fsSL "https://github.com/anchore/syft/releases/download/v${SYFT_VERSION}/syft_${SYFT_VERSION}_linux_amd64.tar.gz" | tar -xz -C /tmp/platform-tools syft; \
    install -m 0755 /tmp/platform-tools/syft /usr/local/bin/syft; \
    curl -fsSL "https://github.com/anchore/grype/releases/download/v${GRYPE_VERSION}/grype_${GRYPE_VERSION}_linux_amd64.tar.gz" | tar -xz -C /tmp/platform-tools grype; \
    install -m 0755 /tmp/platform-tools/grype /usr/local/bin/grype; \
    curl -fsSL "https://github.com/oras-project/oras/releases/download/v${ORAS_VERSION}/oras_${ORAS_VERSION}_linux_amd64.tar.gz" | tar -xz -C /tmp/platform-tools oras; \
    install -m 0755 /tmp/platform-tools/oras /usr/local/bin/oras; \
    rm -rf /tmp/platform-tools

RUN set -eux; \
    mkdir -p /opt/azp; \
    curl -fsSL "https://download.agent.dev.azure.com/agent/${AZP_AGENT_VERSION}/vsts-agent-linux-x64-${AZP_AGENT_VERSION}.tar.gz" -o /tmp/azp-agent.tar.gz; \
    echo "9bda746173092c1cfa1ead92c67ad787711d326fffce6248c9aa2fcf04057065  /tmp/azp-agent.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/azp-agent.tar.gz -C /opt/azp; \
    rm /tmp/azp-agent.tar.gz; \
    /usr/sbin/useradd --uid 10001 --user-group --create-home --home-dir /home/azp azp; \
    mkdir -p /azp/_work; \
    chown -R azp:azp /opt/azp /azp /opt/dotnet-tools

RUN --mount=type=secret,id=asol_internal_ca,required=false \
    set -eux; \
    if [[ -f /run/secrets/asol_internal_ca ]]; then \
      install -m 0644 /run/secrets/asol_internal_ca /usr/local/share/ca-certificates/asol-internal-ca.crt; \
      update-ca-certificates; \
    fi

COPY --chown=azp:azp --chmod=0755 start.sh /opt/azp/start.sh

ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
    JAVA_HOME_21_X64=/usr/lib/jvm/java-21-openjdk-amd64

USER 10001:10001
WORKDIR /opt/azp

ENTRYPOINT ["/opt/azp/start.sh"]
