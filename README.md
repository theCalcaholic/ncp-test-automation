# NCP Test Automation

*This repository provides a set of tools and configuration to simplify testing any version of ncp (for non-docker instances).*

**Disclaimer**: *This project is still in a very early stage and might contain bugs and lack polish. You have been warned :)*

# Requirements

1. Python 3.5+ and virtualenv installed in your system
2. You need [the geckodriver executable](https://github.com/mozilla/geckodriver/releases) in your system path
3. You need [the terraform executable (>= 1.0)](https://www.terraform.io/downloads.html) in your system path
4. You need [the hcloud command line tool](https://github.com/hetznercloud/cli) (`apt install hcloud-cli` on Debian based systems)
5. You need an account and an API key for any project at [Hetzner Cloud](https://hetzner.cloud)

# Setup

1. Clone this repository
2. Inside the cloned repository create the file terraform/terraform.tfvars with the following content:

```hcl
admin_ssh_privkey_path = "/home/your-user/.ssh/your-ssh-key"
admin_ssh_pubkey_path = "/home/your-user/.ssh/your-ssh-key.pub"
hcloud_ncp_playground_api_token = "your-hetzner-cloud-api-token"
```

# Usage

## NCP Installation (curl installer) Test

Run the script `ncp-install-test.sh` inside the `/bin` directory.
You can optionally specify a branch to test, e.g. `./bin/ncp-install-test.sh master` (default is devel).

The script will do the following:

1. Create a server in the hetzner cloud and install ncp on it
2. Create a snapshot from that server and delete the server
3. Create a new server from the snapshot and run automated tests against it (during which, ncp will be activated as a side effect).
4. If the tests succeeded, the snapshot will get a label `test-result=success` and a new snapshot of the activated system will be created
5. Delete the test server

## NCP Update Test

Run the script `ncp-update-test.sh` inside the `/bin` directory.
You can optionally specify a **from** and a **to** branch, e.g. `./bin/ncp-update-test.sh master devel`
(these are the default values and will test the update from the master to the devel branch)
in order to specify from which version of ncp to start and which to update to.

The script will do the following:

1. If not already present: Get a tested post-activation snapshot of the `from` branch by running `ncp-install-test.sh` for it.
2. Create a new server from that snapshot and run `ncp-update branch` on it (where 'branch' is the `to` branch).
3. Run automated tests against that server
4. Delete the test server
