#!/bin/bash

# script/build: build the debian package

COMMAND="help"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# shellcheck source=script/common_functions.sh
source "${SCRIPT_DIR}/common_functions.sh"

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
  for package in devscripts debhelper build-essential; do
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

function build_package() {
  echo "> Clean working directory"
  dh_clean
  echo "> Build package"
  debuild -us -uc
  echo "> Create build directory"
  mkdir -p build
  echo "> Copy package to build directory"
  cp ../*.deb build/
  echo "> Clean working directory"
  dh_clean
}

function release_package() { 
  # local email="${COMMAND_PARAMETERS%% *}"
  # if [[ -z "${email}" ]]; then
  #   echo "Error: email is required"
  #   echo "e.g. \"Quentin Gérôme <qgerome@bluesquarehub.com>\""
  #   exit 1
  # fi
  echo "> Release package"
  # echo "  Email: ${email}"
  echo "${COMMAND_PARAMETERS}"
  EMAIL="${email}" dch "${COMMAND_PARAMETERS#* }"
}
function execute() {
  local command=$1
  local exit_code=0
  case "${command}" in
  build)
    build_package
    exit_properly 0
    ;;
  release)
    release_package
    exit_properly 0
    ;;
  *)
    ;;
  esac
}

set -e

check_requirements_or_exit
parse_commandline "$@"
execute "$COMMAND"