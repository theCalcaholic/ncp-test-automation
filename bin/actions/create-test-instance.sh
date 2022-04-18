#!/bin/bash

set -xe

export branch=${1?}

source ./library.sh

echo "Initialize Terraform"
for path in "$TF_PROJECT_SETUP" "$TF_SNAPSHOT" "$TF_SNAPSHOT_PROVIDER" "$TF_TEST_ENV"
do tf-init "$path"; done

echo "Set up Hetzner project"
hcloud-clear-root-key
tf-apply "$TF_PROJECT_SETUP" "$TF_VAR_FILE"
ssh_pubkey_fprint="$(tf-output "$TF_PROJECT_SETUP" admin_ssh_pubkey_fingerprint)"

ensure-postinstall-snapshot "${ssh_pubkey_fprint}" "${branch}"

tf-apply "$TF_TEST_ENV" "$TF_VAR_FILE" \
-var="snapshot_type=ncp-postinstall" \
-var="branch=${branch}" \
-var="admin_ssh_pubkey_fingerprint=${ssh_pubkey_fprint}"

echo "::set-output name=server_address::$(tf-output "$TF_TEST_ENV" test_server_ipv4)"
echo "::set-output name=snapshot_id::$(tf-output "$TF_TEST_ENV" snapshot_id)"
echo "::set-output name=test_server_id::$(tf-output "$TF_TEST_ENV" test_server_id)"