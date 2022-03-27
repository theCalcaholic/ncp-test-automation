#!/usr/bin/env bash
BIN_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
PROJECT_ROOT="$(realpath "$BIN_DIR/..")"

SSH_OPTIONS=(-o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null")

ssh_control_socket="/dev/shm/ncp-testing-$RANDOM"

. "${PROJECT_ROOT}/lib/bash-args/parse_args.sh"

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

# tf-output path [output-name] [TF OPTIONS]
tf-output() {
  local tf_path="${1?}"
  shift
  args=()
  [[ -z "${1}" ]] || args=("-raw" "$@")

  (
  set -e
  cd "$tf_path" || exit 1
  terraform output "${args[@]}"
  )
}

# ensure-postinstall-snapshot ssh_pubkey_fprint [branch [--force]]
ensure-postinstall-snapshot() {

  local var_file="${PROJECT_ROOT}/terraform/terraform.tfvars"
  local tf_snapshot="${PROJECT_ROOT}/terraform/tasks/snapshot"
  local tf_snapshot_provider="${PROJECT_ROOT}/terraform/tasks/ncp-postinstall/snapshot-provider"
  local ssh_pubkey_fprint=${1}
  local branch="${2:-devel}"

  (
  set -e
  if [[ " $* " =~ .*" --force ".* ]] || ! hcloud image list -t snapshot -l "type=ncp-postinstall,branch=${branch//\//-}" -o noheader -o columns=created | grep -qv -e day  -e week -e year -e month
  then
    trap 'tf-destroy "$tf_snapshot_provider" "$var_file" -var="branch=${branch}" -var="admin_ssh_pubkey_fingerprint=${ssh_pubkey_fprint}"' EXIT
    echo "Creating ncp postinstall snapshot"
    tf-apply "$tf_snapshot_provider" "$var_file" -var="branch=${branch}" -var="admin_ssh_pubkey_fingerprint=${ssh_pubkey_fprint}"
    snapshot_provider_id="$(tf-output "$tf_snapshot_provider" snapshot_provider_id)"
    tf-apply "$tf_snapshot" "$var_file" -var="branch=${branch}" -var="snapshot_provider_id=${snapshot_provider_id}" -var="snapshot_type=ncp-postinstall" -state="${tf_snapshot}/${branch//\//.}.postinstall.tfstate"
    tf-destroy "$tf_snapshot_provider" "$var_file" -var="branch=${branch}" -var="admin_ssh_pubkey_fingerprint=${ssh_pubkey_fprint}"
  else
    echo "Reusing existing ncp postinstall snapshot"
  fi
  )
}

# setup-ssh-port-forwarding server-address
setup-ssh-port-forwarding() {
  ssh-keygen -f "$HOME/.ssh/known_hosts" -R "${1?}" 2> /dev/null
  ssh "${SSH_OPTIONS[@]}" root@"${1}" <<EOF || return $?
    set -e
    sed -i -e 's/AllowTcpForwarding.*/AllowTcpForwarding yes/' -e 's/PermitOpen.*/PermitOpen any/g' /etc/ssh/sshd_config
    systemctl restart ssh
EOF
  ssh "${SSH_OPTIONS[@]}" -M -S "$ssh_control_socket" -fNT \
    -L 8443:127.0.0.1:443 -L 9443:127.0.0.1:4443 root@"${1}" <<EOF
    tail -f /var/log/ncp.log &
    sleep 600
EOF
}

# terminate-ssh-port-forwarding server-address
terminate-ssh-port-forwarding() {
    ssh -S "$ssh_control_socket" -O exit "root@${1:-stub}"
}

# test-ncp-instance ssh-connection server-address nc-port webui-port [--branch] [--activate] [--flag-snapshot snapshot-id]
test-ncp-instance() {

  local DESCRIPTION="Runs automated integration tests against an ncp instance"
  local KEYWORDS=("-a|--activate;bool" "-f|--flag-snapshot" "-n|--non-interactive;bool" "-b|--branch")
  local REQUIRED=("ssh-connection" "server-address" "nc-port" "webui-port")
  local -A USAGE
  USAGE['server]']="The address (IP address, URL, ...) of the ncp instance. Needs to be reachable passwordless via ssh with user root"
  USAGE['ssh-connection']="How to connect to the server via ssh in the format user@server-address"
  USAGE['server-address']="The address where the server can be reached via https"
  USAGE['nc-port']="The port where Nextcloud can be reached (i.e. at https://server-address:nc-port)"
  USAGE['webui-port']="The port where the admin web UI can be reached (i.e. at https://server-address:webui-port)"
  USAGE['-a']="Perform activation test first (requires fresh, not activated ncp installation)"
  USAGE['-f']="flag snapshot given as snapshot id with test result (success or failure)"
  USAGE['-n']="Omit all interactive dialogs (and assume default answer)"
  USAGE['-b']="Specify the branch to checkout for the ncp integration tests (default: master)"

  parse_args "$@" || exit $?

  snapshot_id="${KW_ARGS['--flag-snapshot']:-${KW_ARGS['-f']}}"

  NCP_AUTOMATION_DIR="$(mktemp -d)"

  (
  set -e

  trap '[[ -z "$NCP_AUTOMATION_DIR" ]] || rm -rf "$NCP_AUTOMATION_DIR"' EXIT

  cd "${NCP_AUTOMATION_DIR?}"

  virtualenv "$NCP_AUTOMATION_DIR/venv"
  . "$NCP_AUTOMATION_DIR/venv/bin/activate"
  pip install selenium
  git clone https://github.com/nextcloud/nextcloudpi.git
  cd nextcloudpi/tests
  git checkout "${KW_ARGS['-b']:-master}"

  failed=no

  if [[ "${KW_ARGS['-a']:-${KW_ARGS['--activate']}}" == "true" ]]
  then
    python activation_tests.py "${NAMED_ARGS['server-address']}" "${NAMED_ARGS['nc-port']}" "${NAMED_ARGS['webui-port']}" || {
      echo "======================="
      echo "Activation test failed!"

      [[ "${KW_ARGS['-n']}" != "true" ]] || exit 2
      echo "You can also connect to the instance with 'ssh root@<server-ip>' for troubleshooting."
      read -n 1 -rp "Continue anyway (will tear down the server)? (y|N)" choice
      [[ "${choice,,}" == "y" ]] || {
        echo ""
        exit 2
      }
      failed=yes
    }
    [[ "$failed" == "yes" ]] || {
      scp "${SSH_OPTIONS[@]}" ./test_cfg.txt "${NAMED_ARGS['ssh-connection']}:/root/ncp_test_cfg.txt"
    }
  else
    scp "${SSH_OPTIONS[@]}" "${NAMED_ARGS['ssh-connection']}:/root/ncp_test_cfg.txt" ./test_cfg.txt 2> /dev/null || {
      echo "Could not load test config. Tests will be interactive." >&2
    }
  fi

  python system_tests.py "${NAMED_ARGS['ssh-connection']}" || {
    echo "System test failed!"
    failed=yes
  }
  python nextcloud_tests.py "${NAMED_ARGS['server-address']}" "${NAMED_ARGS['nc-port']}" "${NAMED_ARGS['webui-port']}" || {
    echo "Nextcloud test failed!"
    failed=yes
  }

  [[ "$failed" != "yes" ]] || {
    [[ -z "$snapshot_id" ]] || hcloud image add-label -o "$snapshot_id" "test-result=failure"
    exit 2
  }

  echo "All tests succeeded"
  [[ -z "$snapshot_id" ]] || hcloud image add-label -o "$snapshot_id" "test-result=success"

  )

}
