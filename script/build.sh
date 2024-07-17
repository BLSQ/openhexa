#!/bin/bash

# script/build: build the debian package

function is_docker_installed() {
  docker 2>/dev/null
}

function is_docker_26_installed() {
  local docker_version_string major_docker_version
  docker_version_string=$(docker --version)
  docker_version_string=${docker_version_string/Docker version/}
  major_docker_version=${docker_version_string/\.[[:digit:]\.]*.*/}
  ((major_docker_version >= 26))
}

function is_package_installed() {
  local package_name=$1
  dpkg-query -W -f='${Status}' "${package_name}" | grep -q "install ok installed"
}

function is_linux_distribution_debian_like() {
  grep -q "^ID.*=debian" /etc/os-release
}

function check_requirements_or_exit() {
  echo "> Check requirements:"
  echo -n "  Debian-like distribution ..."
  if is_linux_distribution_debian_like; then
    echo "OK"
  else
    echo "KO"
    echo "Please run this script in a Debian like distribution."
    exit 1
  fi
  echo -n "  docker 26+ ... "
  if is_docker_installed && is_docker_26_installed; then
    echo "OK"
  else
    echo "KO"
    echo """
    Please install at least docker 26. See
    https://docs.docker.com/engine/install/debian/ for further
    instructions.
    """
    exit 1
  fi
  for package in devscripts debhelper build-essential openssl; do
    echo -n "  ${package} ... "
    if is_package_installed "${package}"; then
      echo "OK"
    else
      echo "KO"
      echo "Please install ${package}: apt install ${package}"
      exit 1
    fi
  done
}

set -e

cd "$(dirname "$0")/.."

check_requirements_or_exit

echo "> Clean working directory"
dh_clean
echo "> Build package"
debuild -us -uc
