FROM debian:stable AS builder

RUN apt-get update && apt-get install -y python3 python3-pip build-essential python3-dev libffi-dev libssl-dev python3-venv
RUN python3 -m venv /venv && /venv/bin/pip install selenium

FROM debian:stable

ENV SSH_PRIVATE_KEY=""
ENV SSH_PUBLIC_KEY=""
ENV HCLOUD_TOKEN=""
ENV DOCKER=true

RUN apt-get update && apt-get install -y extrepo && extrepo enable mozilla \
    && apt-get update && apt-get install -y python3 python3-pip bash git openssh-client firefox jq wget unzip
COPY --from=builder /venv /venv
WORKDIR /usr/local/bin/
RUN wget -qO - https://github.com/mozilla/geckodriver/releases/download/v0.36.0/geckodriver-v0.36.0-linux64.tar.gz | tar xz \
    && chmod +x /usr/local/bin/geckodriver
RUN wget -qO terraform.zip https://releases.hashicorp.com/terraform/1.1.8/terraform_1.1.8_linux_amd64.zip \
    && unzip terraform.zip \
    && rm terraform.zip \
    && chmod +x /usr/local/bin/terraform
RUN wget -qO - https://github.com/hetznercloud/cli/releases/download/v1.43.0/hcloud-linux-amd64.tar.gz | tar xz \
    && chmod +x /usr/local/bin/hcloud
RUN groupadd github && useradd -g github github
COPY --chown=github:github bin /ncp-test-automation/bin
COPY --chown=github:github terraform /ncp-test-automation/terraform
COPY --chown=github:github lib /ncp-test-automation/lib

WORKDIR /ncp-test-automation/bin
ENTRYPOINT ["/bin/bash", "/ncp-test-automation/bin/entrypoint.sh"]
