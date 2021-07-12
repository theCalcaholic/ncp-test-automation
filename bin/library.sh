#!/usr/bin/env bash

# tf-apply path var-file args
tf-apply() {
  local tf_path="${1?}"
  shift
  local tf_varfile="${1?}"
  shift
  args=("$@")

  (
  cd "$tf_path" || exit 1
  rc=0
  terraform apply -auto-approve -var-file="$tf_varfile" "${args[@]}" || rc=$?
  [[ $rc -eq 0 ]] || terraform destroy -auto-approve -var-file="$tf_varfile" "${args[@]}"
  exit $rc
  )
}

# tf-destroy path var-file args
tf-destroy() {
  local tf_path="${1?}"
  shift
  local tf_varfile="${1?}"
  shift
  args=("$@")

  (
  set -e
  cd "$tf_path" || exit 1
  terraform destroy -auto-approve -var-file="$tf_varfile" "${args[@]}"
  )
}

# tf-output path [output-name]
tf-output() {
  local tf_path="${1?}"
  shift
  args=()
  [[ -z "${1}" ]] || args=("-raw" "${1}")

  (
  set -e
  cd "$tf_path" || exit 1
  terraform output "${args[@]}"
  )
}

# ensure-postinstall-snapshot ssh_pubkey_fprint [branch [--force]]
ensure-postinstall-snapshot() {


  local script_dir="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
  local project_root="$(realpath "$script_dir/..")"
  local var_file="${project_root}/terraform/terraform.tfvars"
  local tf_snapshot="${project_root}/terraform/tasks/snapshot"
  local tf_snapshot_provider="${project_root}/terraform/tasks/ncp-postinstall/snapshot-provider"
  local ssh_pubkey_fprint=${1}
  local branch="${2:-devel}"

  (
  set -e
  if [[ " $* " =~ .*" --force ".* ]] || ! hcloud image list -t snapshot -l "type=ncp-postinstall,branch=${branch//\/-}" -o noheader -o columns=created | grep -qv -e day  -e week -e year -e month
  then
    trap 'tf-destroy "$tf_snapshot_provider" "$var_file" -var="branch=${branch}" -var="admin_ssh_pubkey_fingerprint=${ssh_pubkey_fprint}"' EXIT
    echo "Creating ncp postinstall snapshot"
    tf-apply "$tf_snapshot_provider" "$var_file" -var="branch=${branch}" -var="admin_ssh_pubkey_fingerprint=${ssh_pubkey_fprint}"
    snapshot_provider_id="$(tf-output "$tf_snapshot_provider" snapshot_provider_id)"
    tf-apply "$tf_snapshot" "$var_file" -var="branch=${branch}" -var="snapshot_provider_id=${snapshot_provider_id}" -state="${tf_snapshot}/${branch//\//.}.tfstate"
    tf-destroy "$tf_snapshot_provider" "$var_file" -var="branch=${branch}" -var="admin_ssh_pubkey_fingerprint=${ssh_pubkey_fprint}"
    trap - EXIT

  fi
  )
}