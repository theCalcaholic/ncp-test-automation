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

delete_hcloud_images 10

age_limit="$(date +%s)"
age_limit=$((age_limit - (24 * 3600)))
image_found=false
while read -r image_date
do
  image_secs="$(date -d "$image_date" +%s)"
  [[ $age_limit -le $image_secs ]] && {
    image_found=true
    break
  }
done <<<"$(hcloud image list -t snapshot -l "type=ncp-postactivation,branch=${from//\//-},test-result=success${UID:+",ci=${UID}"}" -o noheader -o columns=created)"

if [[ "$image_found" != "true" ]]
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

trap "cleanup \$?; trap - EXIT;" EXIT 1 2

tf-apply "$TF_TEST_ENV" "$TF_VAR_FILE" -var="snapshot_type=ncp-postactivation" -var="branch=${from}" -var="admin_ssh_pubkey_fingerprint=${ssh_pubkey_fprint}"
ipv4_address="$(tf-output "$TF_TEST_ENV" test_server_ipv4)"

ssh-keygen -f "$HOME/.ssh/known_hosts" -R "${ipv4_address}" 2> /dev/null
ssh "${SSH_OPTIONS[@]}" "root@${ipv4_address}" "ncp-update '$to'" || {
  echo "ncp-update failed! Exiting" >&2
  exit 1
}

test_result=success
setup-ssh-port-forwarding "${ipv4_address}"
test-ncp-instance -b "${to}" "root@${ipv4_address}" "localhost" "8443" "9443" || {

   echo "Integration tests failed"
   echo "Here are the last lines of ncp-install.log:"
   echo "==========================================="
   ssh "${SSH_OPTIONS[@]}" "root@${ipv4_address}" tail /var/log/ncp-install.log;
   echo "==========================================="
   echo "and ncp.log:"
   echo "==========================================="
   ssh "${SSH_OPTIONS[@]}" "root@${ipv4_address}" tail /var/log/ncp.log;
   echo "==========================================="

  test_result=failure
}

[[ "$test_result" == "success" ]]
