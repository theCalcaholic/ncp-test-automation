FROM alpine:latest as builder

RUN apk add python3 py3-pip build-base python3-dev musl-dev libffi-dev openssl-dev py3-virtualenv rust cargo
RUN python3 -m venv /venv && /venv/bin/pip install selenium

FROM alpine:latest

ENV SSH_PRIVATE_KEY=""
ENV SSH_PUBLIC_KEY=""
ENV HCLOUD_TOKEN=""
ENV DOCKER=true

RUN apk add python3 py3-pip bash git openssh firefox jq
COPY --from=builder /venv /venv
WORKDIR /usr/local/bin/
RUN wget -qO - https://github.com/mozilla/geckodriver/releases/download/v0.33.0/geckodriver-v0.33.0-linux64.tar.gz | tar xz \
    && chmod +x /usr/local/bin/geckodriver
RUN wget -qO - https://releases.hashicorp.com/terraform/1.1.8/terraform_1.1.8_linux_amd64.zip | busybox unzip - \
    && chmod +x /usr/local/bin/terraform
RUN wget -qO - https://github.com/hetznercloud/cli/releases/download/v1.43.0/hcloud-linux-amd64.tar.gz | tar xz \
    && chmod +x /usr/local/bin/hcloud
RUN addgroup github && adduser -G github -D github
COPY --chown=github:github bin /ncp-test-automation/bin
COPY --chown=github:github terraform /ncp-test-automation/terraform
COPY --chown=github:github lib /ncp-test-automation/lib

WORKDIR /ncp-test-automation/bin
ENTRYPOINT ["/bin/bash", "/ncp-test-automation/bin/entrypoint.sh"]
