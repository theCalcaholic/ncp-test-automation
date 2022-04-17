#!/bin/bash
set -e

mkdir -p ~/.ssh
export SSH_PRIVATE_KEY_PATH="$(echo ~/.ssh/automation_ssh_key)"
export SSH_PUBLIC_KEY_PATH="$(echo ~/.ssh/automation_ssh_key.pub)"
echo "$SSH_PRIVATE_KEY" > "$SSH_PRIVATE_KEY_PATH"
chmod 0600 "$SSH_PRIVATE_KEY_PATH"
echo "$SSH_PUBLIC_KEY" > "$SSH_PUBLIC_KEY_PATH"
eval "$(ssh-agent)"
ssh-add "$SSH_PRIVATE_KEY_PATH"
cat <<EOF > /ncp-test-automation/terraform/terraform.tfvars
admin_ssh_privkey_path = "$SSH_PRIVATE_KEY_PATH"
admin_ssh_pubkey_path = "$SSH_PUBLIC_KEY_PATH"
admin_ssh_pubkey = "$SSH_PUBLIC_KEY"
hcloud_api_token = "$HCLOUD_TOKEN"
EOF

bash "$@"
