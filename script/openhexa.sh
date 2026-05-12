#!/bin/bash

# script/openhexa.sh: command OpenHexa service

OPTION_GLOBAL="off"
COMMAND="help"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# shellcheck source=script/common_functions.sh
source "${SCRIPT_DIR}/common_functions.sh"

function usage() {
  if [[ -z $1 ]]; then
    echo """

    Usage:    $0 [OPTIONS] COMMAND

    OPTIONS:

    -g        executes the OpenHexa command considering OpenHexa has bee globally
              installed on the system. By default, it runs in its current working
              directory

    -d        enables debug output

    COMMANDS:

    start       starts all services
    stop        stops all services
    status      reports current status
    ps          reports running services
    config      reports the config used
    update      pulls last container images
    prepare     runs databases migrations and installs fixtures
    logs        gets all the logs
    backup         backs up OpenHexa
    backup-status  show duplicity collection-status for the workspaces and forgejo backends
    restore        restores OpenHexa, more details with \`help restore\`
    help [cmd]  prints current usage documentation or of the given command \`cmd\`
    version     prints current version
    """
    return
  fi
  local cmd=$1
  case $cmd in
  restore)
    echo """

    Usage:    restore [OPTIONS]

    OPTIONS: none
    """
    # -c        retrieves the backup and checks them, but does not restore it
    #           in place
    ;;
  *)
    echo "The command ${cmd} is unknown."
    usage
    ;;
  esac
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

function is_forgejo_reachable() {
  local port
  port=$(
    load_env 2>/dev/null
    echo "${FORGEJO_PORT:-3100}"
  )
  (($(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${port}/api/v1/version") == 200))
}

function is_db_accepting_connexion() {
  # TODO replace with get_config_or_default
  (
    load_env
    pg_isready -p "${DB_PORT}" >/dev/null 2>&1
  )
  return 0
}

function is_db_reachable_from_backend() {
  run_compose_with_profiles exec app python manage.py check --database default >/dev/null 2>&1
}

function begin_pgsql_session() {
  local pgpassfile db_host db_port db_user db_password
  db_host=$1
  db_port=$2
  db_user=$3
  db_password=$4

  pgpassfile=$(mktemp "$(pwd)/pgpassfile-openhexa.XXXX")
  chmod 0600 "${pgpassfile}"
  echo "${db_host}:${db_port}:*:${db_user}:${db_password}" >"${pgpassfile}"
  echo "${pgpassfile}"
}

function end_pgsql_session() {
  local pgpassfile
  pgpassfile=$1
  rm "${pgpassfile}"
}

function duplicity_parameters_for_some_type() {
  local type=$1
  case $type in
  # s3)
  #   echo "--s3-use-new-style "
  # echo "--s3-region-name eu-central-1"
  # echo "--s3-endpoint-url "
  # ;;
  *) ;;
  esac
}
function require_backup_config() {
  local location passphrase
  if [[ ! -r "$(backup_conf_file)" ]]; then
    echo "Backup not configured: $(backup_conf_file) is missing."
    echo "Run \`setup.sh backup <LOCATION> <PASSPHRASE>\` first."
    return 1
  fi
  location=$(get_backup_config LOCATION)
  passphrase=$(get_backup_config PASSPHRASE)
  if [[ -z $location || -z $passphrase ]]; then
    echo "Backup config $(backup_conf_file) is missing LOCATION or PASSPHRASE."
    return 1
  fi
  return 0
}

function full_if_older_than_arg() {
  local age=$1
  [[ -n $age ]] && echo "--full-if-older-than ${age}"
}

function run_duplicity_backup() {
  local source=$1 target=$2 type=$3 passphrase=$4 oldest_full_age=$5
  # No action verb on purpose: duplicity picks `full` on first run and
  # `incremental` thereafter, so the same command works on empty targets.
  PASSPHRASE=$passphrase \
    duplicity \
    $(duplicity_parameters_for_some_type "${type}") \
    $(full_if_older_than_arg "${oldest_full_age}") \
    "${source}" \
    "${target}"
}

function perform_backup() {
  require_backup_config || return 1
  (
    load_env
    local dumpfile_path envcopy_path type location passphrase oldest_full_age pgpassfile rc=0

    echo -n "Load backup configuration ... "
    type=$(get_backup_config TYPE)
    location=$(get_backup_config LOCATION)
    passphrase=$(get_backup_config PASSPHRASE)
    oldest_full_age=$(get_backup_config OLDEST_FULL_BCK_AGE)
    # case $type in
    # s3)
    #   export AWS_ACCESS_KEY_ID=$(get_backup_config ACCESS_KEY_ID)
    #   export AWS_SECRET_ACCESS_KEY=$(get_backup_config SECRET_ACCESS_KEY)
    #   ;;
    # gs)
    #   export GS_ACCESS_KEY_ID=$(get_backup_config ACCESS_KEY_ID)
    #   export GS_SECRET_ACCESS_KEY=$(get_backup_config SECRET_ACCESS_KEY)
    #   ;;
    # *) ;;
    # esac
    echo "OK"

    echo -n "Prepare dump of the whole PostgreSQL cluster dedicated to OpenHexa ... "
    dumpfile_path="${WORKSPACE_STORAGE_LOCATION}/openhexa-dumpall.sql"
    pgpassfile=$(begin_pgsql_session localhost "${DATABASE_PORT}" "${DATABASE_USER}" "${DATABASE_PASSWORD}")
    PGPASSFILE=$pgpassfile pg_dumpall --file "${dumpfile_path}" --host localhost --port "${DATABASE_PORT}" --username "${DATABASE_USER}"
    end_pgsql_session "${pgpassfile}"
    echo "OK"

    # Snapshot .env alongside the data. ENCRYPTION_KEY, SECRET_KEY,
    # JUPYTERHUB_CRYPT_KEY, HUB_API_TOKEN and the admin passwords live
    # only here; without them a DB restore is unrecoverable.
    echo -n "Stage configuration snapshot (.env) ... "
    envcopy_path="${WORKSPACE_STORAGE_LOCATION}/openhexa-env.bak"
    cp -a "$(dot_env_file)" "${envcopy_path}"
    echo "OK"

    echo "Back up workspace files, PostgreSQL dump, and .env snapshot ..."
    run_duplicity_backup "${WORKSPACE_STORAGE_LOCATION}" "${location}/workspaces" \
      "${type}" "${passphrase}" "${oldest_full_age}" || rc=$?

    if ((rc == 0)); then
      echo "Back up Forgejo data (repos + SQLite metadata) ..."
      run_duplicity_backup "${FORGEJO_STORAGE_LOCATION}" "${location}/forgejo" \
        "${type}" "${passphrase}" "${oldest_full_age}" || rc=$?
    fi

    echo -n "Remove staged DB dump and env snapshot ... "
    rm "${dumpfile_path}" "${envcopy_path}"
    echo "OK"

    if ((rc != 0)); then
      echo "Backup FAILED (duplicity exit ${rc}). The data on the remote target may be incomplete."
    fi
    return $rc
  )
}
function perform_backup_status() {
  require_backup_config || return 1
  local location passphrase rc=0
  location=$(get_backup_config LOCATION)
  passphrase=$(get_backup_config PASSPHRASE)
  for backend in workspaces forgejo; do
    echo "=== ${backend} (${location}/${backend}) ==="
    PASSPHRASE=$passphrase duplicity collection-status "${location}/${backend}" || rc=$?
    echo
  done
  return $rc
}

function perform_restore() {
  require_backup_config || return 1
  (
    load_env
    local location passphrase dumpfile_path envcopy_path pgpassfile psql_exit_code psql_result running_services
    location=$(get_backup_config LOCATION)
    passphrase=$(get_backup_config PASSPHRASE)

    echo -n "Check that no OpenHEXA services are running ... "
    running_services=$(number_of_running_services)
    if ((running_services > 0)); then
      echo "KO"
      echo "Refusing to restore while ${running_services} service(s) are running."
      echo "Active connections would block DROP DATABASE during the dump replay."
      echo "Stop everything first with: ./script/openhexa.sh stop"
      return 1
    fi
    echo "OK"

    echo -n "Keep a copy of the workspace target ... "
    mv "${WORKSPACE_STORAGE_LOCATION}" "${WORKSPACE_STORAGE_LOCATION}-$(date -Iseconds)"
    mkdir "${WORKSPACE_STORAGE_LOCATION}"
    echo "OK"

    echo -n "Restore workspace files ... "
    PASSPHRASE=$passphrase \
      duplicity restore \
      "${location}/workspaces" \
      "${WORKSPACE_STORAGE_LOCATION}"
    echo "OK"

    echo -n "Keep a copy of the Forgejo target ... "
    mv "${FORGEJO_STORAGE_LOCATION}" "${FORGEJO_STORAGE_LOCATION}-$(date -Iseconds)"
    mkdir "${FORGEJO_STORAGE_LOCATION}"
    echo "OK"

    echo -n "Restore Forgejo data ... "
    PASSPHRASE=$passphrase \
      duplicity restore \
      "${location}/forgejo" \
      "${FORGEJO_STORAGE_LOCATION}"
    echo "OK"

    echo -n "Restore PostgreSQL dump ... "
    dumpfile_path="${WORKSPACE_STORAGE_LOCATION}/openhexa-dumpall.sql"
    if [[ ! -r $dumpfile_path ]]; then
      echo "KO: the dump file ${dumpfile_path} is not readable."
      return 1
    fi
    pgpassfile=$(begin_pgsql_session localhost "${DATABASE_PORT}" "${DATABASE_USER}" "${DATABASE_PASSWORD}")
    psql_result=$(PGPASSFILE=$pgpassfile psql -f "${dumpfile_path}" --host localhost --port "${DATABASE_PORT}" --username "${DATABASE_USER}" template1 2>&1)
    psql_exit_code=$?
    end_pgsql_session "${pgpassfile}"
    if [[ $psql_exit_code -eq 0 ]]; then
      echo "OK"
      rm "${dumpfile_path}"
    else
      echo "KO: ${psql_result}"
      return $psql_exit_code
    fi

    envcopy_path="${WORKSPACE_STORAGE_LOCATION}/openhexa-env.bak"
    if [[ -r $envcopy_path ]]; then
      echo "Configuration snapshot restored to ${envcopy_path}."
      echo "Compare it with $(dot_env_file) before discarding; the encryption keys must match the restored database."
    fi
    return 0
  )
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
    echo -n "Forgejo HTTP Reachable: "
    if is_forgejo_reachable; then
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
    run_compose_with_profiles run app fixtures --localhosting
    run_compose_with_profiles run app python manage.py sync_git_orgs
    run_compose_with_profiles run jupyterhub jupyterhub upgrade-db -f /etc/jupyterhub/jupyterhub_dev_config.py
    exit_properly 0
    ;;
  logs)
    run_compose_with_profiles logs
    exit_properly 0
    ;;
  backup)
    perform_backup
    exit_properly $?
    ;;
  backup-status)
    perform_backup_status
    exit_properly $?
    ;;
  restore)
    perform_restore
    exit_properly $?
    ;;
  help)
    usage $COMMAND_PARAMETERS
    exit_properly 0
    ;;
  compose)
    run_compose_with_profiles "$COMMAND_PARAMETERS"
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
