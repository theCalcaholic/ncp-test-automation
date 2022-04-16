FROM alpine:latest

ENV SSH_PRIVATE_KEY=""
ENV SSH_PUBLIC_KEY=""
ENV HCLOUD_API_TOKEN=""

RUN apk add python3 py3-pip bash git openssh
WORKDIR /usr/local/bin/
RUN wget -qO - https://github.com/mozilla/geckodriver/releases/download/v0.31.0/geckodriver-v0.31.0-linux64.tar.gz | tar xz \
    && chmod +x /usr/local/bin/geckodriver
RUN wget -qO - https://releases.hashicorp.com/terraform/1.1.8/terraform_1.1.8_linux_amd64.zip | busybox unzip - \
    && chmod +x /usr/local/bin/terraform
RUN wget -qO - https://github.com/hetznercloud/cli/releases/download/v1.29.4/hcloud-darwin-amd64.tar.gz | tar xz \
    && chmod +x /usr/local/bin/hcloud
COPY bin /ncp-test-automation/bin
COPY terraform /ncp-test-automation/terraform
COPY lib /ncp-test-automation/lib

WORKDIR /ncp-test-automation/bin
ENTRYPOINT ["/bin/bash", "entrypoint.sh"]
