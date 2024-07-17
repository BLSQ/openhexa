#!/bin/bash

# script/setup.sh: setup OpenHexa service

COMMAND="help"
OPTION_GLOBAL="off"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# shellcheck source=script/common_functions.sh
source "${SCRIPT_DIR}/common_functions.sh"

PGSQL_VERSION=""
PGSQL_CLUSTER=""

function usage() {
  echo """
  
  Usage:    $0 [OPTIONS] COMMAND

  OPTIONS:

  -g        executes the OpenHexa command considering OpenHexa has bee globally
            installed on the system. By default, it runs in its current working
            directory

  -d        enables debug output            

  COMMANDS:

  env       sets up the environment and stores it in a file
  db        sets up db
  purge     stops OpenHexa and purges the configuration and the environment
  check     checks installation
  help      prints current usage documentation
  version   prints current version
  """
}

LOCAL_FILES=(
  .env
  .env.dist
  compose.yml
  debian/openhexa.service
  script/common_functions.sh
  script/openhexa.sh
  script/setup.sh
)

INSTALLED_FILES=(
  /etc/openhexa/.env.dist
  /etc/openhexa/env.conf
  /lib/systemd/system/openhexa.service
  /usr/share/openhexa/compose.yml
  /usr/share/openhexa/common_functions.sh
  /usr/share/openhexa/openhexa.sh
  /usr/share/openhexa/setup.sh
)

function is_package_installed() {
  local package_name=$1
  dpkg-query -W -f='${Status}' "${package_name}" | grep -q "install ok installed"
}

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

function is_docker_dependency_installed() {
  echo -n "- docker 26+ ... "
  if is_docker_installed && is_docker_26_installed; then
    echo "installed"
    return 0
  else
    echo "not installed (See installation instructions https://docs.docker.com/engine/install/debian/ )"
    return 1
  fi
}

function is_docker_engine_running() {
  local command
  command="docker info"
  [[ $OPTION_GLOBAL == "on" ]] && command="${SUDO_COMMAND} $command"

  echo -n "- docker engine is ... "

  if $command >/dev/null 2>&1; then
    echo "running"
    return 0
  else
    echo "not running:"
    if [[ $OPTION_GLOBAL == "on" ]]; then

      cat <<EOF
    If you use Systemd to manage services and you don't run in a container, please
    try the following:
    - Start the services \`sudo systemctl start docker.service containerd.service\`
    - Check their status \`sudo systemctl status docker.service containerd.service\`
    
    For more details see https://docs.docker.com/engine/install/linux-postinstall/

    If you run in a container, you very likely need to share the Docker socket
    with your container and have an image prepared adequately. As it is an
    unusual setup, we let that at the appreciation of the user depending on its
    situation.
EOF
    else
      cat <<EOF
    As a non-root user add yourself to the \`docker\` group:
    - Add your user to the \`docker\` group: \`sudo usermod -aG docker $USER\`
    - Update the current session: \`newgrp docker\`

    For more details see https://docs.docker.com/engine/install/linux-postinstall/
EOF
    fi
    return 1
  fi
}

function is_postgresql_service_running() {
  local result
  echo -n "- postgresql service is ... "
  if pg_isready >/dev/null 2>&1; then
    echo "running"
    return 0
  else
    echo "not running"
    cat <<EOF
    If you use Systemd to manage services and you don't run in a container, please
    try the following with a user having the superuser rights:
    - Start the service \`systemctl start postgresql.service\`
    - Check its the status \`systemctl status postgresql.service\`

    If you use init.d, please try the following with a user having the superuser
    rights (that works also in a container):
    - Start the service \`/etc/init.d/postgresql start\`
    - Check its the status \`/etc/init.d/postgresql status\`    
EOF
    return 1
  fi
}

function is_yq_installed() {
  echo -n "- binary yq ... "
  if [[ $(yq -V) =~ yq.*version\ v.* ]]; then
    echo "installed"
    return 0
  else
    echo "not installed (See https://github.com/mikefarah/yq/#install )"
    return 1
  fi
}

function are_package_dependencies_installed() {
  local exit_code
  exit_code=0
  for package in gettext-base openssl postgresql 'postgresql-*-postgis-3'; do
    echo -n "- package ${package} ... "
    if is_package_installed "${package}"; then
      echo "installed"
    else
      echo "not installed (Do \`apt install ${package}\`)"
      exit_code=1
    fi
  done
  return $exit_code
}

function are_files_installed() {
  local exit_code=0
  local files_to_check
  if [[ $OPTION_GLOBAL == "on" ]]; then
    files_to_check=("${INSTALLED_FILES[@]}")
  else
    files_to_check=("${LOCAL_FILES[@]}")
  fi
  for expected_file in "${files_to_check[@]}"; do
    echo -n "- file $expected_file ... "
    if [[ -r $expected_file ]]; then
      echo "present"
    else
      echo "not present or not readable"
      exit_code=1
    fi
  done
  return $exit_code
}

function is_systemd_service_installed_and_enabled() {
  local result
  echo -n "- Systemd service openhexa.service ... "
  if [[ $OPTION_GLOBAL == "off" ]]; then
    echo "not required (run locally)"
    return 0
  fi
  result=$(systemctl is-enabled openhexa.service)
  case "${result}" in
  enabled)
    echo "enabled"
    return 0
    ;;
  disabled)
    echo "disabled"
    return 1
    ;;
  *)
    echo "not installed"
    return 1
    ;;
  esac
}

function get_postgresql_name_for_port() {
  local port=$1
  pg_lsclusters --no-header | sed -e "s/[[:space:]]\+/,/g" | grep "$port" | cut -d, -f2
}

function get_postgresql_version_for_port() {
  local port=$1
  pg_lsclusters --no-header | sed -e "s/[[:space:]]\+/,/g" | grep "$port" | cut -d, -f1
}

function get_last_postgresql_port() {
  pg_lsclusters --no-header | sed -e "s/[[:space:]]\+/,/g" | cut -d, -f3 | sort | uniq | tail -1
}

function create_postgresql_user() {
  local port username password
  port=$1
  username=$2
  password=$3
  (
    cd /tmp
    $SUDO_COMMAND su postgres <<-EOFSU
psql -p "${port}" <<-EOFPSQL
CREATE USER "${username}" WITH SUPERUSER PASSWORD '${password}'
EOFPSQL
EOFSU
  )
}

function docker_bridge_gateway_address() {
  local address
  address=$(docker network inspect --format='{{(index .IPAM.Config 0).Gateway}}' bridge)
  # on Linux the default gateway IP address is 172.17.0.1
  echo "${address:-172.17.0.1}"
}

function docker_bridge_gateway_subnet() {
  local gateway_address
  gateway_address=$(docker_bridge_gateway_address)
  echo "${gateway_address/.*/}.0.0.0/8"
}

function listen_on_docker_network() {
  local past_listened_addresses gateway_address
  past_listened_addresses="$(pg_conftool -s "${PGSQL_VERSION}" "${PGSQL_CLUSTER}" show listen_addresses || echo "")"
  gateway_address="$(docker_bridge_gateway_address)"
  if [[ -z $past_listened_addresses ]]; then
    pg_conftool "${PGSQL_VERSION}" "${PGSQL_CLUSTER}" set listen_addresses "127.0.0.1,${gateway_address}"
  elif [[ $past_listened_addresses != *$gateway_address* ]]; then
    pg_conftool "${PGSQL_VERSION}" "${PGSQL_CLUSTER}" set listen_addresses "${past_listened_addresses},${gateway_address}"
  fi
}

function allow_access_from_docker() {
  local subnet username dbname pg_hba_file
  subnet=$1
  username=$2
  dbname=$3
  pg_hba_file=$(pg_conftool -s "${PGSQL_VERSION}" "${PGSQL_CLUSTER}" show hba_file)
  $SUDO_COMMAND su -c "printf \"host\t%s\t%s\t%s\tscram-sha-256\n\" \"${dbname}\" \"${username}\" \"${subnet}\" >>\"${pg_hba_file}\""
}

function restart_postgreql() {
  $SUDO_COMMAND pg_ctlcluster "${PGSQL_VERSION}" "${PGSQL_CLUSTER}" restart
}

function create_postgresql_db() {
  local port owner dbname
  port=$1
  owner=$2
  dbname=$3
  (
    cd /tmp
    $SUDO_COMMAND su postgres -c "createdb -p \"${port}\" -O \"${owner}\" \"$dbname\""
  )
}

function dist_dot_env_file() {
  local current_env_file="/etc/openhexa/.env.dist"
  if [[ $OPTION_GLOBAL == "off" ]]; then
    current_env_file=".env.dist"
  fi
  echo "$current_env_file"
}

function setup_env() {
  local db_port
  db_port=$(get_last_postgresql_port)
  [[ ! -r "$(dot_env_file)" ]] && (
    AWS_ACCESS_KEY_ID=$(openssl rand -hex 16) \
    AWS_SECRET_ACCESS_KEY=$(openssl rand -base64 42) \
    DB_PORT=$db_port \
      envsubst <"$(dist_dot_env_file)" >"$(dot_env_file)"
  )
}

function setup_db() {
  PGSQL_VERSION=$(get_postgresql_version_for_port "$DB_PORT")
  PGSQL_CLUSTER=$(get_postgresql_name_for_port "$DB_PORT")

  listen_on_docker_network
  allow_access_from_docker "$(docker_bridge_gateway_subnet)" all all
  restart_postgreql

  create_postgresql_user "$DB_PORT" hexa-app hexa-app
  create_postgresql_db "$DB_PORT" hexa-app hexa-app
  create_postgresql_user "$DB_PORT" hexa-hub hexa-hub
  create_postgresql_db "$DB_PORT" hexa-hub hexa-hub

}

function purge_env() {
  echo "Purge environment:"
  echo -n "- container, network, and volumes ... "
  [[ -f "$(dot_env_file)" ]] && run_compose_with_profiles down --remove-orphans --volumes
  echo "removed"
  echo -n "- configuration file ... "
  [[ -f "$(dot_env_file)" ]] && rm "$(dot_env_file)"
  echo "removed"
}

function drop_postgresql_user() {
  local port username
  port=$1
  username=$2
  (
    cd /tmp
    $SUDO_COMMAND su postgres -c "dropuser --if-exists -p \"${port}\" \"${username}\" 2>/dev/null"
  )
}

function drop_postgresql_db() {
  local port dbname
  port=$1
  dbname=$2
  (
    cd /tmp
    $SUDO_COMMAND su postgres -c "dropdb --if-exists -p \"${port}\" \"$dbname\" 2>/dev/null"
  )
}

function does_db_exist() {
  local port db_name
  port=$1
  db_name=$2
  (
    cd /tmp
    $SUDO_COMMAND su postgres -c "psql -p \"${port}\" -lqt | cut -d \| -f 1 | grep -qw \"${db_name}\""
  )
}

function does_table_exist() {
  local port db_name table_name
  port=$1
  db_name=$2
  table_name=$3
  (
    cd /tmp
    $SUDO_COMMAND su postgres -c "psql -p \"${port}\" -tXAc \"SELECT EXISTS( SELECT FROM pg_tables WHERE schemaname='${db_name}' AND tablename='${table_name}');\" | grep -q t"
  )
}

function does_user_exist() {
  local port username
  port=$1
  username=$2
  (
    cd /tmp
    $SUDO_COMMAND su postgres -c "psql -p \"${port}\" -tXAc \"SELECT 1 FROM pg_roles WHERE rolname='$username';\" | grep -q 1"
  )
}

function list_openhexa_db_workspaces() {
  local port
  port=$1
  if does_db_exist "${port}" hexa-app && does_table_exist "${port}" hexa-app workspaces_workspace; then
    (
      cd /tmp
      $SUDO_COMMAND su postgres -c "psql -p \"${port}\" hexa-app -Atc \"SELECT db_name FROM workspaces_workspace;\""
    )
  elif does_user_exist "${port}" hexa-app; then
    (
      cd /tmp
      $SUDO_COMMAND su postgres -c "psql -p \"${port}\" -Atc \"SELECT datname FROM pg_database JOIN pg_authid ON pg_database.datdba = pg_authid.oid WHERE has_database_privilege('hexa-app', datname, 'CONNECT') AND rolname <> 'postgres';\""
    )
  else
    echo ""
  fi
}

function purge_db() {
  local db_port
  db_port=$(get_last_postgresql_port)

  echo "Purge database:"

  for workspace_db in $(list_openhexa_db_workspaces "$db_port"); do
    echo -n "- workspace database ${workspace_db} ... "
    drop_postgresql_db "$db_port" "$workspace_db"
    echo -n "dropped db ... "
    drop_postgresql_user "$db_port" "$workspace_db"
    echo "dropped user"
  done
  for app_db in hexa-app hexa-hub; do
    echo -n "- app database ${app_db} ... "
    drop_postgresql_db "$db_port" "$app_db"
    echo -n "dropped db ... "
    drop_postgresql_user "$db_port" "$app_db"
    echo "dropped user"

  done
}

function execute() {
  local command=$1
  local exit_code=0
  case "${command}" in
  env)
    setup_env
    exit_properly 0
    ;;
  db)
    load_env
    setup_db
    exit_properly 0
    ;;
  purge)
    purge_env
    purge_db
    exit_properly 0
    ;;
  check)
    echo "Check installation:"
    are_files_installed
    exit_code=$?
    is_systemd_service_installed_and_enabled || exit_code=1
    are_package_dependencies_installed || exit_code=1
    is_yq_installed || exit_code=1
    is_docker_dependency_installed || exit_code=1
    is_docker_engine_running || exit_code=1
    is_postgresql_service_running || exit_code=1
    exit_properly $exit_code
    ;;
  help)
    usage
    exit_properly 0
    ;;
  version)
    echo "OpenHexa Setup 1.0"
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
