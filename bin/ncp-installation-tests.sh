#!/usr/bin/env bash

branch="${1:-devel}"

set -e

. ./library.sh

var_file="${PROJECT_ROOT}/terraform/terraform.tfvars"
tf_tasks_root="${PROJECT_ROOT}/terraform/tasks"
tf_project_setup="${tf_tasks_root}/project-setup"
tf_snapshot="${tf_tasks_root}/snapshot"
tf_snapshot_provider="${tf_tasks_root}/ncp-postinstall/snapshot-provider"
tf_test_env="${tf_tasks_root}/ncp-postinstall/test-environment"

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
  set -x
  (
    set +e
    terminate-ssh-port-forwarding "${ipv4_address}"
    tf-destroy "$tf_test_env" "$var_file" -var="branch=${branch}" -var="admin_ssh_pubkey_fingerprint=${ssh_pubkey_fprint}"
    exit 0
  )
}

trap "cleanup; trap - EXIT;" EXIT 1 2
tf-apply "$tf_test_env" "$var_file" -var="branch=${branch}" -var="admin_ssh_pubkey_fingerprint=${ssh_pubkey_fprint}"
ipv4_address="$(tf-output "$tf_test_env" test_server_ipv4)"
snapshot_id="$(tf-output "$tf_test_env" snapshot_id)"

setup-ssh-port-forwarding "${ipv4_address}"
test-ncp-instance -a -f "$snapshot_id" "root@${ipv4_address}" "localhost" "8443" "9443"
