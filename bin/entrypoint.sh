#!/bin/bash
set -e

cd "$(dirname "${BASH_SOURCE[0]}")"
export HOME=/root

mkdir -p ~/.ssh
export SSH_PRIVATE_KEY_PATH="/github/workspace/.ssh/automation_ssh_key"
export SSH_PUBLIC_KEY_PATH="/github/workspace/.ssh/automation_ssh_key.pub"
[[ -z "$SSH_PRIVATE_KEY" ]] || {
  echo "$SSH_PRIVATE_KEY" > "$SSH_PRIVATE_KEY_PATH"
  chmod 0600 "$SSH_PRIVATE_KEY_PATH"
}
[[ -z "$SSH_PUBLIC_KEY" ]] || echo "$SSH_PUBLIC_KEY" > "$SSH_PUBLIC_KEY_PATH"
[[ -f "$SSH_PRIVATE_KEY_PATH" ]] && {
  eval "$(ssh-agent)"
  ssh-add "$SSH_PRIVATE_KEY_PATH"
}
cat <<EOF > /ncp-test-automation/terraform/terraform.tfvars
admin_ssh_privkey_path = "$SSH_PRIVATE_KEY_PATH"
admin_ssh_pubkey_path = "$SSH_PUBLIC_KEY_PATH"
admin_ssh_pubkey = "$SSH_PUBLIC_KEY"
hcloud_api_token = "$HCLOUD_TOKEN"
uid_suffix = "${UID:+-$UID}"
server_type = "${SERVER_TYPE:-cx22}"
EOF

bash "$@"
