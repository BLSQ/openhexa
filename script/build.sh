#!/bin/bash
#
# script/build: A robust script to build the Debian package.
#

# --- Shell Best Practices ---
set -euo pipefail

# --- Constants and Colors ---
readonly BUILD_DIR="build"
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_NONE='\033[0m'

#  Functions

function is_package_installed() {
  local package_name="$1"
  dpkg-query -W -f='${Status}' "${package_name}" 2>/dev/null | grep -q "install ok installed"
}

function is_linux_distribution_debian_like() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "${ID:-}" == "debian" || "${ID_LIKE:-}" =~ "debian" ]]; then
      return 0
    fi
  fi
  return 1
}

function check_requirements_or_exit() {
  echo "> Checking build requirements..."
  local missing_packages=()

  if ! is_linux_distribution_debian_like; then
    echo -e "${COLOR_RED}Error: This script must be run on a Debian-based distribution (e.g., Debian, Ubuntu, Mint).${COLOR_NONE}" >&2
    exit 1
  fi
  echo -e "  - Debian-based distribution... ${COLOR_GREEN}OK${COLOR_NONE}"

  if ! command -v debuild >/dev/null 2>&1; then
    missing_packages+=("devscripts")
  fi

  for pkg in debhelper build-essential; do
    if ! is_package_installed "$pkg"; then
      missing_packages+=("$pkg")
    fi
  done

  if [[ ${#missing_packages[@]} -gt 0 ]]; then
    echo -e "${COLOR_RED}Error: The following required packages are missing:${COLOR_NONE}" >&2
    printf "  - %s\n" "${missing_packages[@]}" >&2
    echo -e "\nPlease install them by running:\n  sudo apt update && sudo apt install ${missing_packages[*]}" >&2
    exit 1
  fi
  echo -e "  - All required packages found... ${COLOR_GREEN}OK${COLOR_NONE}"
}

function main() {
  trap 'echo; echo "> Cleaning up build artifacts..."; dh_clean' EXIT

  check_requirements_or_exit

  echo "> Performing initial cleanup..."
  dh_clean

  echo "> Building the Debian package..."
  debuild -us -uc

  echo "> Staging the final package..."
  mkdir -p "$BUILD_DIR"

  local deb_file
  deb_file=$(ls -t ../*.deb 2>/dev/null | head -n 1)

  if [[ -z "${deb_file:-}" ]]; then
    echo -e "${COLOR_RED}Error: Build failed or no .deb package was produced.${COLOR_NONE}" >&2
    exit 1
  fi

  mv "$deb_file" "$BUILD_DIR/"
  echo "  - Package moved to the '$BUILD_DIR/' directory."

  echo -e "\n${COLOR_GREEN}✔ Build successful!${COLOR_NONE}"
}

main "$@"
