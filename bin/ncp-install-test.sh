#!/usr/bin/env bash

branch="${1:-devel}"

set -e

. ./library.sh

var_file="${PROJECT_ROOT}/terraform/terraform.tfvars"
tf_tasks_root="${PROJECT_ROOT}/terraform/tasks"
tf_project_setup="${tf_tasks_root}/project-setup"
tf_snapshot="${tf_tasks_root}/snapshot"
tf_snapshot_provider="${tf_tasks_root}/ncp-postinstall/snapshot-provider"
tf_test_env="${tf_tasks_root}/test-environment"

echo "Initialize Terraform"
for path in "$tf_project_setup" "$tf_snapshot" "$tf_snapshot_provider" "$tf_test_env"
do
  echo "Initializing $(basename "$path")..."
  (
  cd "$path" || exit 1
  terraform init
  )
  echo "done"
done

echo "Setting up project"

tf-apply "$tf_project_setup" "$var_file"
ssh_pubkey_fprint="$(tf-output "$tf_project_setup" admin_ssh_pubkey_fingerprint)"

ensure-postinstall-snapshot "$ssh_pubkey_fprint" "$branch" || {
  echo "Could not create ncp postinstall snapshot (and none was present)"
  exit 1
}

cleanup() {
  (
    set +e
    terminate-ssh-port-forwarding "${ipv4_address}"
    tf-destroy "$tf_test_env" "$var_file" -var="snapshot_type=ncp-postinstall" -var="branch=${branch}" -var="admin_ssh_pubkey_fingerprint=${ssh_pubkey_fprint}"
  )
  exit "$1"
}

trap "cleanup \$?; trap - EXIT;" EXIT 1 2
tf-apply "$tf_test_env" "$var_file" -var="snapshot_type=ncp-postinstall" -var="branch=${branch}" -var="admin_ssh_pubkey_fingerprint=${ssh_pubkey_fprint}"
ipv4_address="$(tf-output "$tf_test_env" test_server_ipv4)"
snapshot_id="$(tf-output "$tf_test_env" snapshot_id)"
test_server_id="$(tf-output "$tf_test_env" test_server_id)"

setup-ssh-port-forwarding "${ipv4_address}"
test-ncp-instance -a -f "$snapshot_id" -b "${branch}" "root@${ipv4_address}" "localhost" "8443" "9443" || (
  echo "Here are the last lines of ncp-install.log:"
  echo "==========================================="
  ssh -o StrictHostKeyChecking=no "root@${ipv4_address}" tail /var/log/ncp-install.log;
  echo "==========================================="
  echo "and ncp.log:"
  echo "==========================================="
  ssh -o StrictHostKeyChecking=no "root@${ipv4_address}" tail /var/log/ncp.log;
  echo "==========================================="
  exit $?;
)

ssh "root@${ipv4_address}" 'systemctl poweroff'
tf-apply "$tf_snapshot" "$var_file" -var="branch=${branch}" -var="snapshot_provider_id=${test_server_id}" -var="snapshot_type=ncp-postactivation" -state="${tf_snapshot}/${branch//\//.}.postactivation.tfstate"
snapshot_id="$(tf-output "$tf_snapshot" -state="${tf_snapshot}/${branch//\//.}.postactivation.tfstate" snapshot_id)"
hcloud image add-label -o "$snapshot_id" "test-result=success"
