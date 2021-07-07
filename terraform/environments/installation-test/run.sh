#!/usr/bin/env bash

(
  set -e
  cd "$(dirname "$0")"
  echo "Setting up infrastructure"

  branch="${1:-devel}"
  tmpdir="$(mktemp -d)"
  trap "terraform destroy; rm -rf \$tmpdir; ssh -S ncp-testing -O exit root@\${ipv4_address}" EXIT 1 2
  terraform apply -var="branch=${branch}"
  ipv4_address="$(terraform output -raw test_server_ipv4)"
  ssh-keygen -f "$HOME/.ssh/known_hosts" -R "${ipv4_address}" 2> /dev/null
  ssh -o "StrictHostKeyChecking=no" \
    -M -S ncp-testing -fNT \
    -L 8443:127.0.0.1:443 -L 9443:127.0.0.1:4443 root@"${ipv4_address}"
  cd "$tmpdir"
  virtualenv "$tmpdir/venv"
  . "$tmpdir/venv/bin/activate"
  pip install selenium
  git clone https://github.com/nextcloud/nextcloudpi.git
  cd nextcloudpi/tests
  git checkout "${branch}"

  failed=no

  python activation_tests.py "localhost" "8443" "9443" || {
    echo "Activation test failed!"

    read -rp "Continue anyway? (y|N)" choice
    [[ "${choice,,}" == "y" ]] || exit 2
    failed=yes
  }
  python system_tests.py "root@${ipv4_address}" || {
    echo "System test failed!"
    failed=yes
  }
  python nextcloud_test.py "localhost" "8443" "9443" || {
    echo "Nextcloud test failed!"
    failed=yes
  }

  [[ "failed" != "yes" ]] || exit 2

  echo "All tests succeeded"

)