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

  -d        enables debug output

  COMMANDS:

  start     starts all services
  stop      stops all services
  status    reports current status
  ps        reports running services
  config    reports the config used
  update    pulls last container images
  prepare   runs database migrations and installs fixtures
  logs      gets all the logs
  help      prints current usage documentation
  version   prints current version
  """
}

function list_of_services() {
  local service_to_exclude="jupyter"
  yq ".services | keys | map(select(. != \"${service_to_exclude}\")) | join(\"\n\")" "${COMPOSE_FILE_PATH}"
}

function number_of_services() {
  list_of_services | wc -l
}

function list_of_running_services() {
  run_compose_with_profiles ps --format '{{.Names}}' --status running
}

function number_of_running_services() {
  list_of_running_services | wc -l
}

function is_service_running() {
  local service=$1
  list_of_running_services | grep -q "${service}\(-[0-9]\+\)\?"
}

function check_running_status_of_each_service() {
  for service in $(list_of_services); do
    echo -n "- ${service} ... "
    if is_service_running "${service}"; then
      echo "running"
    else
      echo "not running or healthy"
    fi
  done
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

function is_db_accepting_connexion() {
  load_env
  pg_isready -p "${DB_PORT}" >/dev/null 2>&1
  return 0
}

function is_db_reachable_from_backend() {
  run_compose_with_profiles exec app python manage.py check --database default >/dev/null 2>&1
}

function execute() {
  local command=$1
  local exit_code=0
  case "${command}" in
  start)
    run_compose_with_profiles up --wait --wait-timeout 60 --remove-orphans
    exit_properly 0
    ;;
  stop)
    run_compose_with_profiles stop
    exit_properly 0
    ;;
  status)
    echo -n "Running: "
    if is_all_services_running; then
      echo "All $(number_of_services)"
    else
      echo "Only $(number_of_running_services) of the $(number_of_services) services are running"
      exit_code=1
    fi
    check_running_status_of_each_service
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
    echo "PostgreSQL: "
    echo -n "- accepting connections: "
    if is_db_accepting_connexion; then
      echo "Yes"
    else
      echo "No"
      exit_code=1
    fi
    echo -n "- reachable from Django app: "
    if is_db_reachable_from_backend; then
      echo "Yes"
    else
      echo "No"
      exit_code=1
    fi
    exit_properly $exit_code
    ;;
  config)
    run_compose_with_profiles config
    exit_properly 0
    ;;
  ps)
    run_compose_with_profiles ps
    exit_properly 0
    ;;
  update)
    run_compose_with_profiles --profile spawned-notebook pull --policy always
    exit_properly 0
    ;;
  prepare)
    run_compose_with_profiles run app fixtures
    exit_properly 0
    ;;
  logs)
    run_compose_with_profiles logs
    exit_properly 0
    ;;
  help)
    usage
    exit_properly 0
    ;;
  version)
    echo "OpenHexa 1.0"
    exit_properly 0
    ;;
  *)
    usage
    exit_properly 1
    ;;
  esac
}

parse_commandline "$@"
enable_debug_if_required
setup
execute "$COMMAND"
