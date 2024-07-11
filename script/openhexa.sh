#!/bin/bash

OPTION_GLOBAL="off"
COMMAND="help"

COMPOSE_FILE_PATH="compose.yml"
CONFIG_FILE_PATH=".env"

function setup() {
  if [[ $OPTION_GLOBAL == "on" ]]; then
    COMPOSE_FILE_PATH="/usr/share/openhexa/compose.yml"
    CONFIG_FILE_PATH="/etc/openhexa/env.conf"
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

function usage() {
  echo """
  
  Usage:    $0 [OPTIONS] COMMAND

  OPTIONS:

  -g        executes the OpenHexa command considering OpenHexa has bee globally
            installed on the system. By default, it runs in its current working
            directory 

  COMMANDS:

  start     starts all services
  stop      stops all services
  status    reports current status
  ps        reports running services
  update    pulls last container images
  prepare   runs database migrations and installs fixtures
  logs      gets all the logs
  help      prints current usage documentation
  version   prints current version
  """
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

function execute() {
  local nbr_of_healthy_services
  local command=$1
  case "${command}" in
  start)
    run_compose_with_profiles up --wait --wait-timeout 60 --remove-orphans
    exit 0
    ;;
  stop)
    run_compose_with_profiles stop
    exit 0
    ;;
  status)
    number_of_running_services=$(run_compose_with_profiles ps --status running --quiet | wc -l)
    if ((number_of_running_services == 8)); then
      echo "Running"
      exit 0
    else
      echo "Only ${number_of_running_services} services are running"
      exit 0
    fi
    ;;
  ps)
    run_compose_with_profiles ps
    exit 0
    ;;
  update)
    run_compose_with_profiles --profile spwaned-notebook pull --policy always
    exit 0
    ;;
  prepare)
    run_compose_with_profiles run app fixtures
    exit 0
    ;;
  logs)
    run_compose_with_profiles logs
    exit 0
    ;;
  help)
    usage
    exit 0
    ;;
  version)
    echo "OpenHexa 1.0"
    exit 0
    ;;
  *)
    usage
    exit 1
    ;;
  esac
}

parse_commandline "$@"
setup
execute "$COMMAND"
