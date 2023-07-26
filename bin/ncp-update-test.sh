#!/usr/bin/env bash

from="${1:-master}"
to="${2:-devel}"

set -ex

. "$(cd "${BASHSOURCE[0]}"; pwd)/library.sh"

echo "Initialize Terraform"
for path in "$TF_PROJECT_SETUP" "$TF_TEST_ENV"
do
  tf-init "$path";
done

echo "Setting up project"

hcloud-clear-root-key
tf-apply "$TF_PROJECT_SETUP" "$TF_VAR_FILE"
ssh_pubkey_fprint="$(tf-output "$TF_PROJECT_SETUP" admin_ssh_pubkey_fingerprint)"

if ! hcloud image list -t snapshot -l "type=ncp-postactivation,branch=${from//\//-}" -o noheader -o columns=created | grep -v day | grep -v week | grep -v year | grep -qv month
then
  "$(cd "${BASHSOURCE[0]}"; pwd)/ncp-install-test.sh" "${from}"
fi

cleanup() {
  (
    set +e
    terminate-ssh-port-forwarding "${ipv4_address}"
    tf-destroy "$TF_TEST_ENV" "$TF_VAR_FILE" -var="snapshot_type=ncp-postactivation" -var="branch=${from}" -var="admin_ssh_pubkey_fingerprint=${ssh_pubkey_fprint}"
  )
  exit "$1"
}

tf-apply "$TF_TEST_ENV" "$TF_VAR_FILE" -var="snapshot_type=ncp-postactivation" -var="branch=${from}" -var="admin_ssh_pubkey_fingerprint=${ssh_pubkey_fprint}"
ipv4_address="$(tf-output "$TF_TEST_ENV" test_server_ipv4)"

ssh-keygen -f "$HOME/.ssh/known_hosts" -R "${ipv4_address}" 2> /dev/null
ssh -o "StrictHostKeyChecking=no" "root@${ipv4_address}" "ncp-update '$to'" || {
  echo "ncp-update failed! Exiting" >&2
  exit 1
}

setup-ssh-port-forwarding "${ipv4_address}"
test-ncp-instance -b "${to}" "root@${ipv4_address}" "localhost" "8443" "9443"

[[ "$test_result" == "success" ]]
