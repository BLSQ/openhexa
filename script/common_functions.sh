COMPOSE_FILE_PATH="compose.yml"
CONFIG_FILE_PATH=".env"
BACKUP_CONFIG_FILE_PATH="backup.conf"
WORKSPACE_DATA_DIRECTORY="workspaces"

SUDO_COMMAND="sudo"

function dot_env_file() {
  echo "${CONFIG_FILE_PATH}"
}

function backup_conf_file() {
  echo "${BACKUP_CONFIG_FILE_PATH}"
}

function load_env() {
  # shellcheck source=.env.dist
  source "${CONFIG_FILE_PATH}"
}

function setup() {
  if [[ $OPTION_GLOBAL == "on" ]]; then
    COMPOSE_FILE_PATH="/usr/share/openhexa/compose.yml"
    CONFIG_FILE_PATH="/etc/openhexa/env.conf"
    BACKUP_CONFIG_FILE_PATH="/etc/openhexa/backup.conf"
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

function dist_dot_env_file() {
  local current_env_file="/etc/openhexa/.env.dist"
  if [[ $OPTION_GLOBAL == "off" ]]; then
    current_env_file=".env.dist"
  fi
  echo "$current_env_file"
}

function get_backup_config() {
  local variable_name=$1
  local backup_file
  if [[ -r "$(backup_conf_file)" ]] && backup_file=$(backup_conf_file); then
    (
      source "${backup_file}"
      echo "${!variable_name}"
    )
  fi
}

function get_config_or_default() {
  local variable_name=$1
  local env_file
  env_file=$(dist_dot_env_file)
  [[ -r "$(dot_env_file)" ]] && env_file=$(dot_env_file)
  (
    # shellcheck source=.env.dist
    source "${env_file}"
    echo "${!variable_name}"
  )
}

function get_proxy_url() {
  local proxy_url
  proxy_url=$(get_config_or_default PROXY_URL)
  if [[ -n $proxy_url ]]; then
    echo "${proxy_url}"
  fi
}

function run_compose() {
  local proxy_url
  local oh_uid
  local oh_gid
  local docker_gid
  proxy_url=$(get_proxy_url)
  oh_uid=$(id -u openhexa)
  oh_gid=$(id -g openhexa)
  docker_gid=$(getent group docker | cut -d: -f3)
  OPENHEXA_CONF_FILE="${CONFIG_FILE_PATH}" \
    NEW_FRONTEND_DOMAIN="${proxy_url}" \
    NOTEBOOKS_URL="${proxy_url}" \
    CORS_ALLOWED_ORIGINS="${proxy_url}" \
    CORS_TRUSTED_ORIGINS="${proxy_url}" \
    OH_UID="${oh_uid}" \
    OH_GID="${oh_gid}" \
    DOCKER_GID="${docker_gid}" \
    docker compose \
    --env-file "${CONFIG_FILE_PATH}" \
    --file "${COMPOSE_FILE_PATH}" \
    --project-name openhexa \
    $@
}

function run_compose_with_profiles() {
  run_compose \
    --profile frontend \
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
  [[ -n $1 ]] && {
    COMMAND="$1"
    shift
    COMMAND_PARAMETERS="$@"
  }
}

function exit_properly() {
  disable_debug
  exit $1
}
