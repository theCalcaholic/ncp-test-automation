# NCP Test Automation

*This repository provides a set of tools and configuration to simplify testing any version of ncp (for non-docker instances).*

# Requirements

1. Python 3.5+ and virtualenv installed in your system
2. You need [the geckodriver executable](https://github.com/mozilla/geckodriver/releases) in your system path
3. You need [the terraform executable (>= 1.0)](https://www.terraform.io/downloads.html) in your system path
4. You need an account and an API key for any project at [Hetzner Cloud](https://hetzner.cloud)

# Setup

1. Clone this repository
2. Inside the cloned repository create the file terraform/environments/installation-test/terraform.tfvars with the following content:

```hcl
admin_ssh_privkey_path = "/home/your-user/.ssh/your-ssh-key"
admin_ssh_pubkey = "ssh-ed25519 YOUR SSH_PUBLIC_KEY AS PASTED FROM /home/your-user/.ssh/your-ssh-key.pub"
hcloud_ncp_playground_api_token = "your-hetzner-cloud-api-token"
```

3. Inside terraform/environments/installation-test run the command `terraform init`

# Usage

1. Run the run.sh script inside the directory terraform/environments/installation-test (more setups will be added in the future).
