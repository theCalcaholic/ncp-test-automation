FROM alpine:latest as builder

RUN apk add python3~=3.9 py3-pip build-base python3-dev musl-dev libffi-dev openssl-dev py3-virtualenv rust cargo
RUN pip install selenium

FROM alpine:latest

ENV SSH_PRIVATE_KEY=""
ENV SSH_PUBLIC_KEY=""
ENV HCLOUD_TOKEN=""
ENV DOCKER=true

RUN apk add python3~=3.9 py3-pip bash git openssh firefox
COPY --from=builder /usr/lib/python3.9/site-packages /usr/lib/python3.9/site-packages
RUN ln -s /usr/bin/python3 /usr/bin/python
WORKDIR /usr/local/bin/
RUN wget -qO - https://github.com/mozilla/geckodriver/releases/download/v0.31.0/geckodriver-v0.31.0-linux64.tar.gz | tar xz \
    && chmod +x /usr/local/bin/geckodriver
RUN wget -qO - https://releases.hashicorp.com/terraform/1.1.8/terraform_1.1.8_linux_amd64.zip | busybox unzip - \
    && chmod +x /usr/local/bin/terraform
RUN wget -qO - https://github.com/hetznercloud/cli/releases/download/v1.29.4/hcloud-linux-amd64.tar.gz | tar xz \
    && chmod +x /usr/local/bin/hcloud
RUN addgroup ncp && adduser -G ncp -D ncp
USER github:github
COPY --chown=ncp:ncp bin /ncp-test-automation/bin
COPY --chown=ncp:ncp terraform /ncp-test-automation/terraform
COPY --chown=ncp:ncp lib /ncp-test-automation/lib

WORKDIR /ncp-test-automation/bin
ENTRYPOINT ["/bin/bash", "entrypoint.sh"]
