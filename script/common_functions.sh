#!/bin/bash

COMPOSE_FILE_PATH="compose.yml"
CONFIG_FILE_PATH=".env"
WORKSPACE_DATA_DIRECTORY="workspaces"

SUDO_COMMAND="sudo"

function dot_env_file() {
  echo "${CONFIG_FILE_PATH}"
}

function load_env() {
  # shellcheck source=.env.dist
  source "${CONFIG_FILE_PATH}"
}

function setup() {
  if [[ $OPTION_GLOBAL == "on" ]]; then
    COMPOSE_FILE_PATH="/usr/share/openhexa/compose.yml"
    CONFIG_FILE_PATH="/etc/openhexa/env.conf"
    WORKSPACE_DATA_DIRECTORY="/var/lib/openhexa/workspaces"
  fi
  if ((UID == 0)); then
    SUDO_COMMAND=""
  fi
}

function enable_debug_if_required() {
  if [[ $OPTION_DEBUG == "on" ]]; then
    set -xv
  fi
}

function disable_debug() {
  set +xv
}

function run_compose() {
  OPENHEXA_CONF_FILE="${CONFIG_FILE_PATH}" \
    docker compose \
    --env-file "${CONFIG_FILE_PATH}" \
    --file "${COMPOSE_FILE_PATH}" \
    --project-name openhexa \
    $@
}

function run_compose_with_profiles() {
  run_compose \
    --profile frontend \
    --profile minio \
    --profile pipelines \
    --profile notebook \
    $@
}

function parse_commandline() {
  while getopts "gd" flag; do
    case "${flag}" in
    g)
      OPTION_GLOBAL="on"
      ;;
    d)
      OPTION_DEBUG="on"
      ;;
    *) ;;
    esac
  done
  shift $((OPTIND - 1))
  [[ -n $1 ]] && COMMAND="$1"
}

function exit_properly() {
  disable_debug
  exit $1
}
