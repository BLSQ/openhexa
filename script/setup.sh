#!/bin/bash

# script/setup.sh: setup OpenHexa service

COMMAND="help"
OPTION_GLOBAL="off"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# shellcheck source=script/common_functions.sh
source "${SCRIPT_DIR}/common_functions.sh"

function postgresql_server_version() {
  pg_config --version | cut -d\  -f2 | cut -d. -f1
}

PGSQL_VERSION=$(postgresql_server_version)
PGSQL_CLUSTER="openhexa"

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

    all       sets up all: first the PostgreSQL database, then the environment
    env       sets up the environment and stores it in a file (requires an
              existing PostgreSQL cluster named \`openhexa\`)
    db        sets up the PostgreSQL database
    purge     stops OpenHexa and purges the configuration and the environment
    check     checks installation
    backup    sets up backup (target location, encryption, frequency, rotation),
              more details with \`help backup\`
    help      prints current usage documentation
    version   prints current version
    """
    return
  fi
  local cmd=$1
  case $cmd in
  backup)
    echo """
      
    Usage:    backup LOCATION PASSPHRASE [OPTIONS]

    LOCATION

    This is the URL of the file server used to store the backup. The following
    type of file servers are supported: local (file://), or SFTP (sftp://).
    The file server AWS S3 (s3://) and Google Cloud Storage (gs://) are under
    development.

    PASSPHRASE

    This is the passphrase to sign and encrypt the backup.

    OPTIONS:

    -f DAYS         the maximum number of days for incremental backup, once
                    beyond it a full backup is performed

    TYPE:

    local
    """
    # To add when working
    # -i ID           the required access key id for files servers Google Cloud Storage
    #                 or AWS s3
    # -s SECRET_KEY   the required secret access key for file servers Google Cloud
    #                 Storage or AWS s3

    ;;
  *)
    echo "The command ${cmd} is unknown."
    usage
    ;;
  esac
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
  echo -n "- postgresql cluster ${PGSQL_CLUSTER} is ... "
  if pg_isready -p $(get_postgresql_port_for_cluster_openhexa) >/dev/null 2>&1; then
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

function does_postgresql_cluster_openhexa_exist() {
  pg_lsclusters --no-header | sed -e "s/[[:space:]]\+/,/g" | cut -d, -f2 | grep -q "^${PGSQL_CLUSTER}$"
}

function get_postgresql_port_for_cluster_openhexa() {
  pg_conftool "${PGSQL_VERSION}" "${PGSQL_CLUSTER}" show port | sed -e "s/^port = //"
}

function create_postgresql_user() {
  local port username password
  port=$1
  username=$2
  password=$3
  (
    cd /tmp
    $SUDO_COMMAND su postgres >/dev/null 2>&1 <<-EOFSU
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
    $SUDO_COMMAND pg_conftool "${PGSQL_VERSION}" "${PGSQL_CLUSTER}" set listen_addresses "127.0.0.1,${gateway_address}"
  elif [[ $past_listened_addresses != *$gateway_address* ]]; then
    $SUDO_COMMAND pg_conftool "${PGSQL_VERSION}" "${PGSQL_CLUSTER}" set listen_addresses "${past_listened_addresses},${gateway_address}"
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
    $SUDO_COMMAND su postgres -c "createdb -p \"${port}\" -O \"${owner}\" \"$dbname\" >/dev/null 2>&1"
  )
}

OPENHEXA_USER=openhexa
OPENHEXA_GROUP=openhexa

function setup_user() {
  if [[ $OPTION_GLOBAL == "on" ]]; then
    $SUDO_COMMAND addgroup --system "${OPENHEXA_GROUP}"
    $SUDO_COMMAND adduser --system --ingroup "${OPENHEXA_GROUP}" "${OPENHEXA_USER}"
    $SUDO_COMMAND usermod -a -G docker "${OPENHEXA_USER}"
  fi
}

function setup_local_storage() {
  if [[ $OPTION_GLOBAL == "on" ]]; then
    $SUDO_COMMAND mkdir -p "${WORKSPACE_DATA_DIRECTORY}"
    $SUDO_COMMAND chown "${OPENHEXA_USER}:${OPENHEXA_GROUP}" "${WORKSPACE_DATA_DIRECTORY}"
  else
    mkdir -p "${WORKSPACE_DATA_DIRECTORY}"
    chmod 777 "${WORKSPACE_DATA_DIRECTORY}"
  fi
}

function generate_django_secret_key() {
  # see https://github.com/django/django/blob/07a4d23283586bc4578eb9c82a7ad14af3724057/django/core/management/utils.py#L79
  # for implementation
  # $ has been removed to avoid bash substitution
  head -c 8192 /dev/urandom | LC_ALL=C tr -dc 'abcdefghijklmnopqrstuvwxyz0123456789!@#%^&*(-_=+)$' | head -c 50
}

function generate_fernet_encryption_key() {
  # see https://github.com/pyca/cryptography/blob/main/src/cryptography/fernet.py#L48
  # for implementation
  # Bash implementation credited to
  # https://github.com/fernet/fernet-rb#generating-a-secret
  dd if=/dev/urandom bs=32 count=1 2>/dev/null | openssl base64
}

function setup_env() {
  local db_port current_working_directory

  echo "Setup environment:"

  if ! does_postgresql_cluster_openhexa_exist >/dev/null 2>&1; then
    echo "The PostgreSQL cluster for OpenHexa hasn't been created."
    echo "Please first run \`$0 db\` or \`$0 all\`."
    return 1
  fi

  db_port=$(get_postgresql_port_for_cluster_openhexa)

  if [[ $OPTION_GLOBAL == "on" ]]; then
    if [[ $(pwd) != "/" ]]; then
      current_working_directory=$(pwd)
    fi
  else
    current_working_directory="$(pwd)/"
  fi

  echo -n "- generate configuration file ... "
  [[ ! -r "$(dot_env_file)" ]] && (
    JUPYTERHUB_CRYPT_KEY=$(openssl rand -hex 32) \
    HUB_API_TOKEN=$(openssl rand -hex 32) \
    SECRET_KEY=$(generate_django_secret_key) \
    ENCRYPTION_KEY=$(generate_fernet_encryption_key) \
    WORKSPACE_STORAGE_LOCATION="${current_working_directory}${WORKSPACE_DATA_DIRECTORY}" \
    DB_PORT=$db_port \
      envsubst <"$(dist_dot_env_file)" >"$(dot_env_file)"
  )
  echo "done"

  echo -n "- create user if installed globally ... "
  setup_user
  echo "done"

  echo -n "- create local storage ... "
  setup_local_storage
  echo "done"
}

function create_pgsql_cluster() {
  $SUDO_COMMAND pg_createcluster "${PGSQL_VERSION}" "${PGSQL_CLUSTER}" --start >/dev/null 2>&1
}

function setup_db() {
  local db_port
  echo "Setup database:"

  echo -n "- create cluster if it does not exists ... "
  if ! does_postgresql_cluster_openhexa_exist; then
    create_pgsql_cluster
    echo "created"
    
    echo -n "- make the cluster listening on the Docker network ... "
    listen_on_docker_network
    echo "done"

    echo -n "- allow access to the cluster from the docker network ... "
    allow_access_from_docker "$(docker_bridge_gateway_subnet)" all all
    echo "done"

    echo -n "- restart the cluster to take in account new setup ... "
    restart_postgreql
    echo "done"

    echo -n "- create users and databases for the Open Hexa app and Jupyter Hub ... "
    db_port=$(get_postgresql_port_for_cluster_openhexa)
    create_postgresql_user "${db_port}" "$(get_config_or_default DATABASE_USER)" "$(get_config_or_default DATABASE_PASSWORD)"
    create_postgresql_db "${db_port}" "$(get_config_or_default DATABASE_NAME)" "$(get_config_or_default DATABASE_USER)"
    create_postgresql_user "${db_port}" "$(get_config_or_default JUPYTERHUB_DATABASE_USER)" "$(get_config_or_default JUPYTERHUB_DATABASE_PASSWORD)"
    create_postgresql_db "${db_port}" "$(get_config_or_default JUPYTERHUB_DATABASE_NAME)" "$(get_config_or_default JUPYTERHUB_DATABASE_USER)"
    echo "done"
  else
    echo "already created"
  fi

  echo -n "- check the cluster is running ... "
  if ! is_postgresql_service_running >/dev/null 2>&1; then
    restart_postgreql
  fi
  echo "running"
}

function remove_user_and_group() {
  local exit_code=0
  if [[ $OPTION_GLOBAL == "on" ]]; then
    deluser --quiet --system "${OPENHEXA_USER}" || exit_code=$?
    delgroup --quiet --system "${OPENHEXA_GROUP}" || exit_code=$?
  fi
  return $exit_code
}

function remove_local_storage() {
  local exit_code=0
  # To use when we set correctly UID when running containers
  # local sudo_if_global="${SUDO_COMMAND}"
  # [[ $OPTION_GLOBAL == "off" ]] && sudo_if_global=""
  # $sudo_if_global find "${WORKSPACE_DATA_DIRECTORY}" -delete 2>/dev/null || exit_code=$?
  $SUDO_COMMAND find "${WORKSPACE_DATA_DIRECTORY}" -delete 2>/dev/null || exit_code=$?
  if (($exit_code != 0)) && [[ ! -d $WORKSPACE_DATA_DIRECTORY ]]; then
    exit_code=0
  fi
  return $exit_code
}

function purge_docker_compose_project() {
  local exit_code=0
  if [[ -f "$(dot_env_file)" ]]; then
    run_compose_with_profiles down --remove-orphans --volumes >/dev/null 2>&1 || exit_code=$?
  fi
  #TODO manage when dot env file is absent but containers are still running
  if docker network inspect openhexa >/dev/null 2>&1; then
    docker network remove openhexa || exit_code=$?
  fi
  return $exit_code
}

function purge_env() {
  echo "Purge environment:"
  echo -n "- container, network, and volumes ... "
  if purge_docker_compose_project; then
    echo "removed"
  else
    echo "failed"
  fi
  echo -n "- configuration file ... "
  if [[ -f "$(dot_env_file)" ]]; then
    if rm "$(dot_env_file)"; then
      echo "removed"
    else
      echo "failed"
    fi
  else
    echo "already removed"
  fi
  echo -n "- user ... "
  if remove_user_and_group; then
    echo "removed"
  else
    echo "failed"
  fi
  echo -n "- workspace data ... "
  if remove_local_storage; then
    echo "removed"
  else
    echo "failed"
  fi
}

function purge_db() {
  echo "Purge database:"
  echo -n "- drop the cluster ${PGSQL_VERSION} ${PGSQL_CLUSTER} ... "
  if does_postgresql_cluster_openhexa_exist; then
    if $SUDO_COMMAND pg_dropcluster --stop "${PGSQL_VERSION}" "${PGSQL_CLUSTER}"; then
      echo "removed"
    else
      echo "failed"
    fi
  else
    echo "already removed"
  fi
}

function prompt_sudo_password_if_needed() {
  if (($EUID != 0)); then
    echo "Some commands require super user right, please answer next SUDO prompt."
    sudo -kv
  fi
}

function url_scheme() {
  local location=$1
  [[ $location =~ ^(([^:  /?#]+):) ]] && echo "${BASH_REMATCH[2]}"
}

function detect_file_server_type() {
  local location=$1
  scheme=$(url_scheme "${location}")
  case $scheme in
  # file | s3 | gs | sftp)
  file | sftp)
    echo "${scheme}"
    ;;
  *)
    echo "The scheme \`${scheme}\` is not supported. Supported file server types are:"
    echo "local file systeme (file://), and SFTP (sftp://)."
    # AWS S3 (s3://), Google Cloud Storage (gs://),
    exit 1
    ;;
  esac
}

function is_duplicity_installed() {
  local version major minor
  duplicity --help >/dev/null 2>&1 || return 1
  version=$(duplicity --version | sed -e "s/duplicity //")
  major=$(echo "${version}" | cut -d. -f1)
  minor=$(echo "${version}" | cut -d. -f2)
  patch=$(echo "${version}" | cut -d. -f3)
  ((major == 0)) && ((minor < 8)) && return 1
  ((major == 0)) && ((minor == 8)) && ((patch < 22)) && return 1
  return 0
}

function is_duplicity_dependency_installed() {
  echo -n "- Duplicity 0.8.22+ (required for backup and restore) ... "
  if is_duplicity_installed; then
    echo "installed"
    return 0
  else
    echo "not installed (Do \`apt install duplicity\`)"
    return 1
  fi
}

function generate_or_update_backup_config() {
  if ! is_duplicity_installed; then
    echo "Duplicity 0.8.22 at least is required. Please install it with"
    echo "\`apt install duplicity\`"
    return 1
  fi
  local location passphrase access_key_id secret_access_key oldest_full_age
  if [[ -z $1 ]]; then
    echo "LOCATION is missing"
    usage backup
    exit 1
  fi

  if [[ -z $2 ]] || [[ $# -eq 3 ]] && [[ $2 =~ ^-[f] ]]; then
    echo "PASSPHRASE is missing"
    usage backup
    exit 1
  fi

  location=$1
  passphrase=$2
  shift 2

  # while getopts "i:s:f:" flag; do
  while getopts "f:" flag; do
    case "${flag}" in
    # i)
    #   access_key_id="${OPTARG}"
    #   ;;
    # s)
    #   secret_access_key="${OPTARG}"
    #   ;;
    f)
      oldest_full_age="${OPTARG}"
      ;;
    *)
      usage backup
      exit_properly 1
      ;;
    esac
  done
  shift $((OPTIND - 1))
  local type
  type=$(detect_file_server_type "${location}")
  echo "- file server location: ${location}"
  echo "- file server type detected: ${type}"
  # case $type in
  # s3 | gs)
  #   if [[ -z $access_key_id ]] || [[ -z $secret_access_key ]]; then
  #     echo "With file server types AWS S3 or Google Cloud Storage, the access key id"
  #     echo "and the secret access key have to be passed:"
  #     echo "backup LOCATION -i <ACCESS_KEY_ID> -s <SECRET_ACCESS_KEY>"
  #     exit 1
  #   else
  #     echo "- access key ID and secret have been provided"
  #   fi
  #   ;;
  # *) ;;
  # esac

  if [[ -n $oldest_full_age ]]; then
    ((oldest_full_age <= 0)) && {
      echo "The number of days before refreshing the backup with a full one should be"
      echo "positive, but \`${oldest_full_age}\` has been passed"
      exit 1
    }
    echo "- maximum period of incremental backup is ${oldest_full_age} days"
  fi

  if [[ -r $(backup_conf_file) ]]; then
    local copy_of_backup_conf
    copy_of_backup_conf="$(backup_conf_file).bck-$(date -Iseconds)"
    echo "- copy the existing backup config file \`${copy_of_backup_conf}\`"
    cp "$(backup_conf_file)" "${copy_of_backup_conf}"
  fi
  echo "- generate the config file OK"
  cat >"$(backup_conf_file)" <<EOF
TYPE=${type}
LOCATION=${location}
PASSPHRASE=${passphrase}
ACCESS_KEY_ID=${access_key_id}
SECRET_KEY_ID=${secret_access_key}
OLDEST_FULL_BCK_AGE=${oldest_full_age}
EOF
}

function execute() {
  local command=$1
  local exit_code=0
  case "${command}" in
  all)
    prompt_sudo_password_if_needed
    setup_db || exit_properly 1
    setup_env || exit_properly 1
    exit_properly 0
    ;;
  env)
    setup_env
    exit_properly 0
    ;;
  db)
    prompt_sudo_password_if_needed
    setup_db
    exit_properly 0
    ;;
  purge)
    prompt_sudo_password_if_needed
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
    is_duplicity_installed
    exit_properly $exit_code
    ;;
  backup)
    echo "Setup backup:"
    generate_or_update_backup_config $COMMAND_PARAMETERS
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
