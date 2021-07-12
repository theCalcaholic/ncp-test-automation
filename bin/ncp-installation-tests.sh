#!/usr/bin/env bash

branch="${1:-devel}"

[[ -n "$NCP_AUTOMATION_DIR" ]] || {
  export NCP_AUTOMATION_DIR="$(mktemp -d)"
}

. ./library.sh

set -e
script_dir="$(realpath "$(dirname "$0")")"
project_root="$(realpath "$script_dir/..")"
var_file="${project_root}/terraform/terraform.tfvars"
tf_tasks_root="${project_root}/terraform/tasks"
tf_project_setup="${tf_tasks_root}/project-setup"
tf_snapshot="${tf_tasks_root}/snapshot"
tf_snapshot_provider="${tf_tasks_root}/ncp-postinstall/snapshot-provider"
tf_test_env="${tf_tasks_root}/ncp-postinstall/test-environment"

ssh_control_socket="/dev/shm/ncp-testing-$RANDOM"

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

#if ! hcloud image list -t snapshot -l "type=ncp-postinstall,branch=${branch}" -o noheader -o columns=created | grep -qv -e day  -e week -e year -e month
#then
#  trap 'tf-destroy "${tf_tasks_root}/ncp-postinstall/snapshot-provider" "$var_file" -var="branch=${branch}" -var="admin_ssh_pubkey_fingerprint=${ssh_pubkey_fprint}"' EXIT
#  echo "Creating ncp postinstall snapshot"
#  tf-apply "$tf_snapshot_provider" "$var_file" -var="branch=${branch}" -var="admin_ssh_pubkey_fingerprint=${ssh_pubkey_fprint}"
#  snapshot_provider_id="$(tf-output "$tf_snapshot_provider" snapshot_provider_id)"
#  tf-apply "$tf_snapshot" "$var_file" -var="branch=${branch}" -var="snapshot_provider_id=${snapshot_provider_id}" -state-out="${tf_snapshot}/${branch}.tfstate"
#  tf-destroy "$tf_snapshot_provider" "$var_file" -var="branch=${branch}" -var="admin_ssh_pubkey_fingerprint=${ssh_pubkey_fprint}"
#  trap - EXIT
#
#fi

ensure-postinstall-snapshot "$ssh_pubkey_fprint" "$branch" || {
  echo "Could not create ncp postinstall snapshot (and none was present)"
  exit 1
}

cleanup() {
  set -x
  (
    set +e
    [[ -z "$NCP_AUTOMATION_DIR" ]] || rm -rf "$NCP_AUTOMATION_DIR"
    ssh -S "$ssh_control_socket" -O exit "root@${ipv4_address}"
    tf-destroy "$tf_test_env" "$var_file" -var="branch=${branch}" -var="admin_ssh_pubkey_fingerprint=${ssh_pubkey_fprint}"
    exit 0
  )
}

trap "cleanup; trap - EXIT;" EXIT 1 2
tf-apply "$tf_test_env" "$var_file" -var="branch=${branch}" -var="admin_ssh_pubkey_fingerprint=${ssh_pubkey_fprint}"
ipv4_address="$(tf-output "$tf_test_env" test_server_ipv4)"
snapshot_id="$(tf-output "$tf_test_env" snapshot_id)"

ssh-keygen -f "$HOME/.ssh/known_hosts" -R "${ipv4_address}" 2> /dev/null
  ssh -o "StrictHostKeyChecking=no" \
    -M -S "$ssh_control_socket" -fNT \
    -L 8443:127.0.0.1:443 -L 9443:127.0.0.1:4443 root@"${ipv4_address}" \
    sleep 600

(
  cd "${NCP_AUTOMATION_DIR?}"

  virtualenv "$NCP_AUTOMATION_DIR/venv"
  . "$NCP_AUTOMATION_DIR/venv/bin/activate"
  pip install selenium
  git clone https://github.com/nextcloud/nextcloudpi.git
  cd nextcloudpi/tests
  git checkout "${branch}"

  failed=no

  python activation_tests.py "localhost" "8443" "9443" || {
    echo "Activation test failed!"

    read -n 1 -rp "Continue anyway? (y|N)" choice
    [[ "${choice,,}" == "y" ]] || exit 2
    failed=yes
  }
  python system_tests.py "root@${ipv4_address}" || {
    echo "System test failed!"
    failed=yes
  }
  python nextcloud_tests.py "localhost" "8443" "9443" || {
    echo "Nextcloud test failed!"
    failed=yes
  }

  [[ "$failed" != "yes" ]] || {
    hcloud image add-label -o "$snapshot_id" "test-result=failure"
    exit 2
  }

  echo "All tests succeeded"
  hcloud image add-label -o "$snapshot_id" "test-result=success"

)
