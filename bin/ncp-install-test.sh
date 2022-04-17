#!/usr/bin/env bash

branch="${1:-devel}"

set -ex

source "$(cd "${BASHSOURCE[0]}"; pwd)/library.sh"

echo "Initialize Terraform"
for path in "$TF_PROJECT_SETUP" "$TF_SNAPSHOT" "$TF_SNAPSHOT_PROVIDER" "$TF_TEST_ENV"
do tf-init "$path"; done

echo "Setting up project"
hcloud_clear_root_key
tf-apply "$TF_PROJECT_SETUP" "$TF_VAR_FILE"
ssh_pubkey_fprint="$(tf-output "$TF_PROJECT_SETUP" admin_ssh_pubkey_fingerprint)"

ensure-postinstall-snapshot "$ssh_pubkey_fprint" "$branch" || {
  echo "Could not create ncp postinstall snapshot (and none was present)"
  exit 1
}

cleanup() {
  (
    set +e
    terminate-ssh-port-forwarding "${ipv4_address}"
    tf-destroy "$TF_TEST_ENV" "$TF_VAR_FILE" -var="snapshot_type=ncp-postinstall" -var="branch=${branch}" -var="admin_ssh_pubkey_fingerprint=${ssh_pubkey_fprint}"
  )
  exit "$1"
}

trap "cleanup \$?; trap - EXIT;" EXIT 1 2
tf-apply "$TF_TEST_ENV" "$TF_VAR_FILE" -var="snapshot_type=ncp-postinstall" -var="branch=${branch}" -var="admin_ssh_pubkey_fingerprint=${ssh_pubkey_fprint}"
ipv4_address="$(tf-output "$TF_TEST_ENV" test_server_ipv4)"
snapshot_id="$(tf-output "$TF_TEST_ENV" snapshot_id)"
test_server_id="$(tf-output "$TF_TEST_ENV" test_server_id)"

setup-ssh-port-forwarding "${ipv4_address}"
test_result=success
test-ncp-instance -a -f "$snapshot_id" -b "${branch}" "root@${ipv4_address}" "localhost" "8443" "9443" || {

  print_failure_message() {

    echo "Integration tests failed"
    echo "Here are the last lines of ncp-install.log:"
    echo "==========================================="
    ssh "${SSH_OPTIONS[@]}" "root@${ipv4_address}" tail /var/log/ncp-install.log;
    echo "==========================================="
    echo "and ncp.log:"
    echo "==========================================="
    ssh "${SSH_OPTIONS[@]}" "root@${ipv4_address}" tail /var/log/ncp.log;
    echo "==========================================="
  }

  echo "WARNING! The integration tests have failed!"

  if [[ $- == *i* ]]
  then
    read -n 1 -rp "Do you want to retry after a reboot? (y|N)" choice
    echo ""
  else
    choice=n
  fi
  if [[ "${choice,,}" == "y" ]]
  then
  # shellcheck disable=SC2029
    ssh "${SSH_OPTIONS[@]}" "root@${ipv4_address}" <<EOF
systemctl stop mariadb
reboot
EOF
    sleep 10
    for i in {9..0}
    do
      ssh "${SSH_OPTIONS[@]}" "root@${ipv4_address}" echo 'Server is back online' && break
      echo "Could not reach server. ${i} Attempts remaining..."
      sleep 10
    done
    clear_args
    test-ncp-instance -f "$snapshot_id" -b "${branch}" "root@${ipv4_address}" "localhost" "8443" "9443" || {
      print_failure_message
      test_result=failure
    }
  else
    print_failure_message
    test_result=failure
  fi
}

ssh "${SSH_OPTIONS[@]}" "root@${ipv4_address}" <<EOF
systemctl stop mariadb
systemctl poweroff
EOF
tf-apply "$TF_SNAPSHOT" "$TF_VAR_FILE" -var="branch=${branch}" -var="snapshot_provider_id=${test_server_id}" -var="snapshot_type=ncp-postactivation" -state="${TF_SNAPSHOT}/${branch//\//.}.postactivation.tfstate"
snapshot_id="$(tf-output "$TF_SNAPSHOT" -state="${TF_SNAPSHOT}/${branch//\//.}.postactivation.tfstate" snapshot_id)"
hcloud image add-label -o "$snapshot_id" "test-result=${test_result}"

[[ "$test_result" == "success" ]]
