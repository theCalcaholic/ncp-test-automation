#!/usr/bin/env bash

from="${1:-master}"
to="${2:-devel}"

set -e

. "$(cd "${BASHSOURCE[0]}"; pwd)/library.sh"
var_file="${PROJECT_ROOT}/terraform/terraform.tfvars"
tf_tasks_root="${PROJECT_ROOT}/terraform/tasks"
tf_project_setup="${tf_tasks_root}/project-setup"
tf_test_env="${tf_tasks_root}/test-environment"

echo "Initialize Terraform"
for path in "$tf_project_setup" "$tf_test_env"
do
  echo "Initializing $(basename "$path")..."
  (
  cd "$path" || exit 1
  terraform init
  )
  echo "done"
done

echo "Setting up project"

hcloud ssh-key describe root > /dev/null 2>&1 && hcloud ssh-key delete root
tf-apply "$tf_project_setup" "$var_file"
ssh_pubkey_fprint="$(tf-output "$tf_project_setup" admin_ssh_pubkey_fingerprint)"

if ! hcloud image list -t snapshot -l "type=ncp-postactivation,branch=${from//\//-}" -o noheader -o columns=created | grep -v day | grep -v week | grep -v year | grep -qv month
then
  "$(cd "${BASHSOURCE[0]}"; pwd)/ncp-install-test.sh" "${from}"
fi

cleanup() {
  (
    set +e
    terminate-ssh-port-forwarding "${ipv4_address}"
    tf-destroy "$tf_test_env" "$var_file" -var="snapshot_type=ncp-postactivation" -var="branch=${from}" -var="admin_ssh_pubkey_fingerprint=${ssh_pubkey_fprint}"
  )
  exit "$1"
}

tf-apply "$tf_test_env" "$var_file" -var="snapshot_type=ncp-postactivation" -var="branch=${from}" -var="admin_ssh_pubkey_fingerprint=${ssh_pubkey_fprint}"
ipv4_address="$(tf-output "$tf_test_env" test_server_ipv4)"

ssh-keygen -f "$HOME/.ssh/known_hosts" -R "${ipv4_address}" 2> /dev/null
ssh -o "StrictHostKeyChecking=no" "root@${ipv4_address}" "ncp-update '$to'" || {
  echo "ncp-update failed! Exiting" >&2
  exit 1
}

setup-ssh-port-forwarding "${ipv4_address}"
test-ncp-instance -b "${to}" "root@${ipv4_address}" "localhost" "8443" "9443"
