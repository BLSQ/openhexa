#!/bin/bash

COMPOSE_FILE_PATH="compose.yml"
CONFIG_FILE_PATH=".env"

SUDO_COMMAND="sudo"

function setup() {
  if [[ $OPTION_GLOBAL == "on" ]]; then
    COMPOSE_FILE_PATH="/usr/share/openhexa/compose.yml"
    CONFIG_FILE_PATH="/etc/openhexa/env.conf"
  fi
  if ((UID == 0)); then
    SUDO_COMMAND=""
  fi
}

function run_compose() {
  docker compose \
    --file "${COMPOSE_FILE_PATH}" \
    --env-file "${CONFIG_FILE_PATH}" \
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
  while getopts "g" flag; do
    case "${flag}" in
    g)
      OPTION_GLOBAL="on"
      ;;
    *) ;;
    esac
  done
  shift $((OPTIND - 1))
  [[ -n $1 ]] && COMMAND="$1"
}
