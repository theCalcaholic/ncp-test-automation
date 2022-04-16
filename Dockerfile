FROM alpine:latest

RUN apk add python3 py3-pip bash git
WORKDIR /usr/local/bin/
RUN wget -qO - https://github.com/mozilla/geckodriver/releases/download/v0.31.0/geckodriver-v0.31.0-linux64.tar.gz | tar xz \
    && chmod +x /usr/local/bin/geckodriver
RUN wget -qO - https://releases.hashicorp.com/terraform/1.1.8/terraform_1.1.8_linux_amd64.zip | busybox unzip - \
    && chmod +x /usr/local/bin/terraform
RUN wget -qO - https://github.com/hetznercloud/cli/releases/download/v1.29.4/hcloud-darwin-amd64.tar.gz | tar xz \
    && chmod +x /usr/local/bin/hcloud
COPY bin lib terraform /ncp-test-automation/

WORKDIR /ncp-test-automation
ENTRYPOINT ["/bin/bash"]
