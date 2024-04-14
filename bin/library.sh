#!/usr/bin/env bash
BIN_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
PROJECT_ROOT="$(realpath "$BIN_DIR/..")"

ssh_control_socket="/dev/shm/ncp-testing-${UID:-$RANDOM}"

SSH_OPTIONS=(-o "StrictHostKeyChecking=no" -o "UserKnownHostsFile=/dev/null")
SSH_SOCKET_OPTIONS=()
[[ -n "$DOCKER" ]] || SSH_SOCKET_OPTIONS+=(-S "$ssh_control_socket")
[[ -z "$SSH_PRIVATE_KEY_PATH" ]] || SSH_OPTIONS+=(-i "${SSH_PRIVATE_KEY_PATH}")

PYTHON="$(which python)"
[[ -f "/venv/bin/python" ]] && PYTHON="/venv/bin/python"

export TF_VAR_FILE="${PROJECT_ROOT}/terraform/terraform.tfvars"
export TF_TASKS_ROOT="${PROJECT_ROOT}/terraform/tasks"
export TF_PROJECT_SETUP="${TF_TASKS_ROOT}/project-setup"
export TF_SNAPSHOT="${TF_TASKS_ROOT}/snapshot"
export TF_SNAPSHOT_PROVIDER="${TF_TASKS_ROOT}/ncp-postinstall/snapshot-provider"
export TF_TEST_ENV="${TF_TASKS_ROOT}/test-environment"


. "${PROJECT_ROOT}/lib/bash-args/parse_args.sh"

hcloud-clear-root-key() {
  if hcloud ssh-key describe "root${UID:+-$UID}" > /dev/null 2>&1
  then
    echo "Deleting ssh key 'root${UID:+-UID}'..."
    hcloud ssh-key delete "root${UID:+-$UID}"
    echo "done."
  fi
}

tf-init() {
  echo "Initializing $(basename "${1?}")..."
  (
  cd "$1" || return 1
  terraform init
  )
  echo "done"
}

# tf-apply path var-file args
tf-apply() {
  local tf_path="${1?}"
  shift
  local tf_varfile="${1?}"
  shift
  args=("$@")

  (
  cd "$tf_path" || return 1
  rc=0
  terraform apply -auto-approve -var-file="$tf_varfile" "${args[@]}" || rc=$?
  [[ $rc -eq 0 ]] || terraform destroy -auto-approve -var-file="$tf_varfile" "${args[@]}"
  return $rc
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
  cd "$tf_path" || return 1
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
  cd "$tf_path" || return 1
  terraform output "${args[@]}"
  )
}

# ensure-postinstall-snapshot ssh_pubkey_fprint [branch [--force]]
ensure-postinstall-snapshot() {

  local ssh_pubkey_fprint=${1}
  local branch="${2:-devel}"

  (
  set -e
  age_limit="$(date +%s)"
  age_limit=$((age_limit - (24 * 3600)))
  image_found=false
  while read -r image_date
  do
    [[ -n "$image_date" ]] || continue
    image_secs="$(date -d "$image_date" +%s)"
    [[ $age_limit -le $image_secs ]] && {
      image_found=true
      break
    }
  done <<<"$(hcloud image list -t snapshot -l "type=ncp-postinstall,branch=${branch//\//-},test-result=success${UID:+",ci=${UID}"}" -o noheader -o columns=created)"

  if [[ " $* " =~ .*" --force ".* ]] || [[ "$image_found" != "true" ]]
  then
    trap 'tf-destroy "$TF_SNAPSHOT_PROVIDER" "$TF_VAR_FILE" -var="branch=${branch}" -var="admin_ssh_pubkey_fingerprint=${ssh_pubkey_fprint}"' EXIT
    echo "Creating ncp postinstall snapshot"
    tf-apply "$TF_SNAPSHOT_PROVIDER" "$TF_VAR_FILE" -var="branch=${branch}" -var="admin_ssh_pubkey_fingerprint=${ssh_pubkey_fprint}" || return $?
    snapshot_provider_id="$(tf-output "$TF_SNAPSHOT_PROVIDER" snapshot_provider_id)"
    tf-apply "$TF_SNAPSHOT" "$TF_VAR_FILE" -var="branch=${branch}" -var="snapshot_provider_id=${snapshot_provider_id}" -var="snapshot_type=ncp-postinstall" -state="${TF_SNAPSHOT}/${branch//\//.}.postinstall.tfstate" || return $?
    tf-destroy "$TF_SNAPSHOT_PROVIDER" "$TF_VAR_FILE" -var="branch=${branch}" -var="admin_ssh_pubkey_fingerprint=${ssh_pubkey_fprint}"
  else
    echo "Reusing existing ncp postinstall snapshot"
  fi
  )
}

# setup-ssh-port-forwarding server-address
setup-ssh-port-forwarding() {
  [[ -f "$HOME/.ssh/known_hosts" ]] && ssh-keygen -f "$HOME/.ssh/known_hosts" -R "${1?}" 2> /dev/null
  ssh "${SSH_OPTIONS[@]}" root@"${1}" <<EOF || return $?
    set -e
    sed -i -e 's/AllowTcpForwarding.*/AllowTcpForwarding yes/' -e 's/PermitOpen.*/PermitOpen any/g' /etc/ssh/sshd_config
    systemctl restart ssh
EOF
  ssh "${SSH_SOCKET_OPTIONS[@]}" "${SSH_OPTIONS[@]}" -M -fNT \
    -L 8443:127.0.0.1:443 -L 9443:127.0.0.1:4443 root@"${1}" <<EOF
    tail -f /var/log/ncp.log &
    sleep 600
EOF
}

# terminate-ssh-port-forwarding server-address
terminate-ssh-port-forwarding() {
  if [[ -z "$DOCKER" ]]
  then
    ssh -S "$ssh_control_socket" -O exit "root@${1:-stub}"
  else
    pkill ssh || true
  fi
}

# test-ncp-instance ssh-connection server-address nc-port webui-port [--branch] [--activate] [--flag-snapshot snapshot-id]
test-ncp-instance() {

  local DESCRIPTION="Runs automated integration tests against an ncp instance"
  local KEYWORDS=("-a|--activate;bool" "-f|--flag-snapshot" "-n|--non-interactive;bool" "-b|--branch" "--systemtest-args", "--nc-test-args")
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
  USAGE['--systemtest-args']="Additional parameters to system_test.py"
  USAGE['--nc-test-args']="Additional parameters to nextcloud_test.py"

  parse_args "$@" || return $?

  snapshot_id="${KW_ARGS['--flag-snapshot']:-${KW_ARGS['-f']}}"

  NCP_AUTOMATION_DIR="$(mktemp -d)"

  (
  set -e

  trap '[[ -z "$NCP_AUTOMATION_DIR" ]] || rm -rf "$NCP_AUTOMATION_DIR"' EXIT

  cd "${NCP_AUTOMATION_DIR?}"

  [[ -n "$DOCKER" ]] || {
    virtualenv "$NCP_AUTOMATION_DIR/venv"
    . "$NCP_AUTOMATION_DIR/venv/bin/activate"
  }
  pip install selenium
  git clone https://github.com/nextcloud/nextcloudpi.git
  cd nextcloudpi/tests
  git checkout "${KW_ARGS['-b']:-master}"

  failed=no
  test_args=()
  [[ -n "$DISPLAY" ]] || test_args+=("--no-gui")

  if [[ "${KW_ARGS['-a']:-${KW_ARGS['--activate']}}" == "true" ]]
  then
    "$PYTHON" activation_tests.py "${test_args[@]}" "${NAMED_ARGS['server-address']}" "${NAMED_ARGS['nc-port']}" "${NAMED_ARGS['webui-port']}" || {
      tail -n 20 geckodriver.log >&2 || true
      echo "======================="
      echo "Activation test failed!"

      [[ "${KW_ARGS['-n']}" != "true" ]] || return 2
      echo "You can also connect to the instance with 'ssh root@<server-ip>' for troubleshooting."
      if [[ -t 0 ]]
      then
        read -n 1 -rp "Continue anyway (will tear down the server)? (y|N)" choice
      else
        choice=n
      fi
      [[ "${choice,,}" == "y" ]] || {
        echo ""
        return 2
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

  sys_test_args=()
  [[ -z "${KW_ARGS['--systemtest-args']}" ]] || IFS=' ' read -r -a sys_test_args <<<"${KW_ARGS['--systemtest-args']}"
  [[ "$CI" == "true" ]] && sys_test_args+=("--no-ping")
  echo "Running system test with arguments: '${sys_test_args[*]}'"
  "$PYTHON" system_tests.py "${sys_test_args[@]}" "${NAMED_ARGS['ssh-connection']}" || {
    echo "System test failed!"
    failed=yes
  }
  nc_test_args=()
  [[ -z "${KW_ARGS['--nc-test-args']}" ]] || IFS=' ' read -r -a nc_test_args <<<"${KW_ARGS['--nc-test-args']}"
  "$PYTHON" nextcloud_tests.py "${test_args[@]}" "${nc_test_args[@]}" "${NAMED_ARGS['server-address']}" "${NAMED_ARGS['nc-port']}" "${NAMED_ARGS['webui-port']}" || {
    echo "Nextcloud test failed!"
    failed=yes
  }

  [[ "$failed" != "yes" ]] || {
    [[ -z "$snapshot_id" ]] || hcloud image add-label -o "$snapshot_id" "test-result=failure"
    return 2
  }

  echo "All tests succeeded"
  [[ -z "$snapshot_id" ]] || hcloud image add-label -o "$snapshot_id" "test-result=success"

  )

}

# Deletes the latest hcloud images, keeping $1 (default: 1)
delete_hcloud_images() {
  for img in $(hcloud image list -t snapshot -o noheader -o columns=id | head -n "-${1:-1}")
  do
    hcloud image delete "$img"
  done
}
