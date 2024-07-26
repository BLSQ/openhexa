#!/bin/bash

# script/openhexa.sh: command OpenHexa service

OPTION_GLOBAL="off"
COMMAND="help"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# shellcheck source=script/common_functions.sh
source "${SCRIPT_DIR}/common_functions.sh"

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

function number_of_services() {
  local service_to_exclude="jupyter"
  yq ".services | keys | map(select(. != \"${service_to_exclude}\")) | length" "${COMPOSE_FILE_PATH}"
}

function number_of_running_services() {
  run_compose_with_profiles ps --status running --quiet | wc -l
}

function is_all_services_running() {
  (($(number_of_services) == $(number_of_running_services)))
}

function is_frontend_reachable() {
  (($(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ready/) == 200))
}

function is_backend_reachable() {
  (($(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/ready) == 200))
}

function execute() {
  local command=$1
  local exit_code=0
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
    echo -n "Running: "
    if is_all_services_running; then
      echo "All $(number_of_services)"
    else
      echo "Only $(number_of_running_services) of the $(number_of_services) services are running"
      exit_code=1
    fi
    echo -n "Frontend HTTP Reachable: "
    if is_frontend_reachable; then
      echo "Yes"
    else
      echo "No"
      exit_code=1
    fi
    echo -n "Backend HTTP Reachable: "
    if is_backend_reachable; then
      echo "Yes"
    else
      echo "No"
      exit_code=1
    fi
    exit $exit_code
    ;;
  ps)
    run_compose_with_profiles ps
    exit 0
    ;;
  update)
    run_compose_with_profiles --profile spawned-notebook pull --policy always
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
