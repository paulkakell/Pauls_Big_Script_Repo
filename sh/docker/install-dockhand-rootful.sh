#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="install-dockhand-rootful"
SCRIPT_VERSION="2026.07.06-r1-rootful"
DEFAULT_SCRIPT_URL="https://raw.githubusercontent.com/paulkakell/Pauls_Big_Script_Repo/main/sh/docker/install-dockhand-rootful.sh"
SCRIPT_URL="${SCRIPT_URL:-$DEFAULT_SCRIPT_URL}"
LOCAL_SCRIPT="/usr/local/sbin/install-dockhand-rootful"
UPDATE_HELPER="/usr/local/bin/dockhand-rootful-installer-update"
CONF_DIR="/etc/dockhand-rootful-installer"
CONF_FILE="$CONF_DIR/install.conf"
LOG_DIR="/var/log"
LOG_FILE="$LOG_DIR/dockhand-rootful-install-$(date +%Y%m%d-%H%M%S).log"

USE_DEFAULTS="no"
ROLLBACK_ON_FAIL="unset"
UPDATE_SELF="no"
SHOW_HELP="no"
INSTALL_STAGE="start"
TOTAL_STEPS=11
CURRENT_STEP=0

DOCKER_SOCKET="/var/run/docker.sock"
DOCKER_HOST="unix://$DOCKER_SOCKET"
DOCKER_SERVICE="docker.service"
DOCKER_SOCKET_SERVICE="docker.socket"
CONTAINERD_SERVICE="containerd.service"

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_BOLD=$'\033[1m'
else
  C_RESET=""
  C_RED=""
  C_GREEN=""
  C_YELLOW=""
  C_BLUE=""
  C_BOLD=""
fi

usage() {
  cat <<EOF
$SCRIPT_NAME $SCRIPT_VERSION

Usage:
  bash install-dockhand-rootful.sh [options]

Options:
  -y, --yes, --defaults       Use defaults and do not prompt.
  --script-url URL            Raw GitHub URL used by the self-update helper.
  --rollback                  Roll back the Dockhand compose stack if deployment fails.
  --no-rollback               Do not roll back on deployment failure.
  --update-self               Download this installer from SCRIPT_URL into $LOCAL_SCRIPT.
  -h, --help                  Show this help.

Environment overrides:
  HOST_PATH                   Default: /dockershare/containers
  INSTALL_PATH                Default: HOST_PATH/dockhand
  DOCKHAND_PORT               Default: 3000
  HOST_DIR_MODE               Default: 0755
  DOCKHAND_IMAGE              Default: fnsys/dockhand:latest
  POSTGRES_IMAGE              Default: postgres:16-alpine
  POSTGRES_PASSWORD           Default: generated
  DOCKHAND_INTERNAL_NETWORK   Default: dockhand-internal
  CONTAINERS_EXTERNAL_NETWORK Default: containers-external
  SCRIPT_URL                  Default: $DEFAULT_SCRIPT_URL
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes|--defaults|--non-interactive)
      USE_DEFAULTS="yes"
      ;;
    --script-url)
      [[ $# -ge 2 ]] || { echo "--script-url requires a URL" >&2; exit 2; }
      SCRIPT_URL="$2"
      shift
      ;;
    --rollback)
      ROLLBACK_ON_FAIL="yes"
      ;;
    --no-rollback)
      ROLLBACK_ON_FAIL="no"
      ;;
    --update-self)
      UPDATE_SELF="yes"
      ;;
    -h|--help)
      SHOW_HELP="yes"
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
  shift
done

if [[ "$SHOW_HELP" == "yes" ]]; then
  usage
  exit 0
fi

if [[ $EUID -ne 0 ]]; then
  echo "Run as root."
  exit 1
fi

install -d -m 0755 "$LOG_DIR" "$CONF_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

info() { printf '%s[INFO]%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
fatal() { printf '%s[ERROR]%s %s\n' "$C_RED" "$C_RESET" "$*"; exit 1; }
success() { printf '%s[OK]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
step() { CURRENT_STEP=$((CURRENT_STEP + 1)); printf '\n%s[%s/%s]%s %s%s%s\n' "$C_BLUE" "$CURRENT_STEP" "$TOTAL_STEPS" "$C_RESET" "$C_BOLD" "$*" "$C_RESET"; }

is_yes() {
  case "${1,,}" in
    y|yes|true|1) return 0 ;;
    *) return 1 ;;
  esac
}

ask() {
  local prompt="$1"
  local default="$2"
  local value=""

  if [[ "$USE_DEFAULTS" == "yes" || ! -r /dev/tty ]]; then
    echo "$default"
    return 0
  fi

  printf '%s [%s]: ' "$prompt" "$default" > /dev/tty
  IFS= read -r value < /dev/tty || true
  echo "${value:-$default}"
}

ask_yes_no() {
  local prompt="$1"
  local default="$2"
  local value=""

  if [[ "$USE_DEFAULTS" == "yes" || ! -r /dev/tty ]]; then
    echo "$default"
    return 0
  fi

  while true; do
    printf '%s [%s]: ' "$prompt" "$default" > /dev/tty
    IFS= read -r value < /dev/tty || true
    value="${value:-$default}"
    case "${value,,}" in
      y|yes) echo "yes"; return 0 ;;
      n|no) echo "no"; return 0 ;;
      *) printf 'Enter yes or no.\n' > /dev/tty ;;
    esac
  done
}

random_password() {
  openssl rand -base64 48 | tr -d '=+/[:space:]' | cut -c1-40
}

validate_numeric() {
  local name="$1"
  local value="$2"
  [[ "$value" =~ ^[0-9]+$ ]] || fatal "$name must be numeric. Received: $value"
}

validate_abs_path() {
  local name="$1"
  local value="$2"
  [[ "$value" == /* ]] || fatal "$name must be an absolute path. Received: $value"
  [[ "$value" != *$'\n'* ]] || fatal "$name cannot contain a newline."
}

validate_port() {
  local value="$1"
  validate_numeric "Dockhand port" "$value"
  (( value >= 1 && value <= 65535 )) || fatal "Dockhand port must be between 1 and 65535."
}

validate_docker_name() {
  local label="$1"
  local value="$2"
  [[ "$value" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || fatal "$label contains an invalid Docker name: $value"
}

apt_wait() {
  local locks=(/var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock)
  local waited=0
  while fuser "${locks[@]}" >/dev/null 2>&1; do
    waited=$((waited + 1))
    (( waited <= 180 )) || fatal "Timed out waiting for apt/dpkg locks."
    sleep 2
  done
}

apt_run() {
  apt_wait
  DEBIAN_FRONTEND=noninteractive apt-get "$@"
}

docker_root() {
  DOCKER_HOST="$DOCKER_HOST" docker "$@"
}

docker_compose() {
  (cd "$INSTALL_PATH" && DOCKER_HOST="$DOCKER_HOST" docker compose "$@")
}

self_update() {
  local tmp
  tmp="$(mktemp)"
  info "Downloading installer from $SCRIPT_URL"
  curl -fsSL "$SCRIPT_URL" -o "$tmp"
  bash -n "$tmp"
  install -d -m 0755 "$(dirname "$LOCAL_SCRIPT")"
  install -m 0755 "$tmp" "$LOCAL_SCRIPT"
  rm -f "$tmp"
  success "Installed updated script at $LOCAL_SCRIPT"
}

install_update_helper() {
  install -d -m 0755 "$(dirname "$UPDATE_HELPER")" "$(dirname "$LOCAL_SCRIPT")" "$CONF_DIR"

  cat > "$UPDATE_HELPER" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_URL="${SCRIPT_URL}"
LOCAL_SCRIPT="${LOCAL_SCRIPT}"
tmp=\$(mktemp)
trap 'rm -f "\$tmp"' EXIT
curl -fsSL "\$SCRIPT_URL" -o "\$tmp"
bash -n "\$tmp"
install -d -m 0755 "\$(dirname "\$LOCAL_SCRIPT")"
install -m 0755 "\$tmp" "\$LOCAL_SCRIPT"
echo "Updated \$LOCAL_SCRIPT from \$SCRIPT_URL"
EOF
  chmod 0755 "$UPDATE_HELPER"

  local tmp
  tmp="$(mktemp)"
  if curl -fsSL "$SCRIPT_URL" -o "$tmp" && bash -n "$tmp"; then
    install -m 0755 "$tmp" "$LOCAL_SCRIPT"
    success "Installed local script at $LOCAL_SCRIPT"
  else
    warn "Could not install local script from $SCRIPT_URL. The update helper was still created."
  fi
  rm -f "$tmp"
}

rollback_deploy() {
  [[ "${ROLLBACK_ON_FAIL:-no}" == "yes" ]] || return 0
  [[ -n "${INSTALL_PATH:-}" && -d "${INSTALL_PATH:-/nonexistent}" ]] || return 0

  warn "Rolling back Dockhand compose stack. Persistent files are left on disk."
  docker_compose down --remove-orphans || true
}

on_error() {
  local code=$?
  local line=${BASH_LINENO[0]:-${LINENO}}
  printf '\n%s[ERROR]%s Failed at stage: %s, line: %s, exit code: %s\n' "$C_RED" "$C_RESET" "${INSTALL_STAGE:-unknown}" "$line" "$code"
  printf 'Log file: %s\n' "$LOG_FILE"
  if [[ "${INSTALL_STAGE:-}" == "deploy" || "${INSTALL_STAGE:-}" == "verify" ]]; then
    rollback_deploy || true
  fi
  exit "$code"
}
trap on_error ERR

wait_for_docker() {
  local i
  for i in {1..90}; do
    if docker_root info >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  systemctl --no-pager --full status "$DOCKER_SERVICE" || true
  systemctl --no-pager --full status "$DOCKER_SOCKET_SERVICE" || true
  journalctl -u "$DOCKER_SERVICE" --no-pager -n 120 || true
  fatal "Rootful Docker did not become ready."
}

ensure_docker_network() {
  local network_name="$1"
  local desired_internal="$2"
  local current_internal=""
  local create_args=(network create --driver bridge)

  if [[ "$desired_internal" == "true" ]]; then
    create_args+=(--internal)
  fi

  if docker_root network inspect "$network_name" >/dev/null 2>&1; then
    current_internal="$(docker_root network inspect -f '{{.Internal}}' "$network_name")"
    if [[ "$current_internal" != "$desired_internal" ]]; then
      fatal "Docker network $network_name already exists with Internal=$current_internal. Expected Internal=$desired_internal. Remove or rename that network, then rerun the installer."
    fi
    info "Docker network $network_name already exists with Internal=$current_internal."
  else
    docker_root "${create_args[@]}" "$network_name" >/dev/null
    success "Created Docker network $network_name with Internal=$desired_internal."
  fi
}

container_networks_sorted() {
  local container="$1"

  docker_root inspect \
    -f '{{range $name, $_ := .NetworkSettings.Networks}}{{printf "%s\n" $name}}{{end}}' \
    "$container" 2>/dev/null \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d' \
    | LC_ALL=C sort -u
}

normalize_network_list() {
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d' \
    | LC_ALL=C sort -u \
    | awk '{ out = out (out ? " " : "") $0 } END { print out }'
}

prune_container_networks() {
  local container="$1"
  shift
  local allowed=" $* "
  local network=""

  while IFS= read -r network; do
    [[ -n "$network" ]] || continue
    if [[ "$allowed" != *" $network "* ]]; then
      docker_root network disconnect "$network" "$container" >/dev/null 2>&1 || true
    fi
  done < <(container_networks_sorted "$container" || true)
}

assert_container_networks() {
  local container="$1"
  shift
  local expected=""
  local actual=""

  expected="$(printf '%s\n' "$@" | normalize_network_list)"
  actual="$(container_networks_sorted "$container" | normalize_network_list)"

  if [[ "$actual" != "$expected" ]]; then
    fatal "$container network mismatch. Expected: ${expected:-none}. Actual: ${actual:-none}."
  fi
}

if [[ "$UPDATE_SELF" == "yes" ]]; then
  self_update
  exit 0
fi

printf '%s%s %s%s\n' "$C_BOLD" "$SCRIPT_NAME" "$SCRIPT_VERSION" "$C_RESET"
printf 'Log file: %s\n' "$LOG_FILE"

step "Collect installation settings"
HOST_PATH="$(ask "Default Docker host data path" "${HOST_PATH:-/dockershare/containers}")"
INSTALL_PATH_DEFAULT="${INSTALL_PATH:-$HOST_PATH/dockhand}"
INSTALL_PATH="$(ask "Dockhand install path" "$INSTALL_PATH_DEFAULT")"
DOCKHAND_PORT="$(ask "Dockhand web port" "${DOCKHAND_PORT:-3000}")"
HOST_DIR_MODE="$(ask "Host bind directory mode" "${HOST_DIR_MODE:-0755}")"
DOCKHAND_IMAGE="$(ask "Dockhand image" "${DOCKHAND_IMAGE:-fnsys/dockhand:latest}")"
POSTGRES_IMAGE="$(ask "PostgreSQL image" "${POSTGRES_IMAGE:-postgres:16-alpine}")"
COMPOSE_PROJECT_NAME="$(ask "Compose project name" "${COMPOSE_PROJECT_NAME:-dockhand}")"
DOCKHAND_INTERNAL_NETWORK="${DOCKHAND_INTERNAL_NETWORK:-dockhand-internal}"
CONTAINERS_EXTERNAL_NETWORK="${CONTAINERS_EXTERNAL_NETWORK:-containers-external}"
INSTALL_SELF_UPDATER="$(ask_yes_no "Install local self-update helper" "yes")"

if [[ "$ROLLBACK_ON_FAIL" == "unset" ]]; then
  ROLLBACK_ON_FAIL="$(ask_yes_no "Rollback Dockhand stack if deployment fails" "yes")"
fi

POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"

validate_abs_path "Default Docker host data path" "$HOST_PATH"
validate_abs_path "Dockhand install path" "$INSTALL_PATH"
validate_port "$DOCKHAND_PORT"
[[ "$HOST_DIR_MODE" =~ ^[0-7]{3,4}$ ]] || fatal "Host bind directory mode must be an octal mode, such as 0755 or 1777."
[[ "$COMPOSE_PROJECT_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || fatal "Compose project name contains invalid characters."
validate_docker_name "Dockhand internal network" "$DOCKHAND_INTERNAL_NETWORK"
validate_docker_name "Containers external network" "$CONTAINERS_EXTERNAL_NETWORK"
[[ "$DOCKHAND_INTERNAL_NETWORK" != "$CONTAINERS_EXTERNAL_NETWORK" ]] || fatal "The internal and external Docker networks must use different names."

DOCKHAND_DATA_PATH="$INSTALL_PATH/data"
POSTGRES_DATA_PATH="$INSTALL_PATH/postgres"
SECRETS_DIR="$INSTALL_PATH/secrets"
ENV_FILE="$INSTALL_PATH/.env"
COMPOSE_FILE="$INSTALL_PATH/docker-compose.yml"
PASSWORD_FILE="$SECRETS_DIR/postgres-password.txt"

if [[ -n "$POSTGRES_PASSWORD" ]]; then
  info "Using PostgreSQL password supplied through POSTGRES_PASSWORD."
elif [[ -f "$PASSWORD_FILE" ]]; then
  POSTGRES_PASSWORD="$(tr -d '\r\n' < "$PASSWORD_FILE")"
  if [[ -n "$POSTGRES_PASSWORD" ]]; then
    info "Reusing existing PostgreSQL password from $PASSWORD_FILE."
  else
    POSTGRES_PASSWORD="$(random_password)"
    warn "Existing PostgreSQL password file was empty. Generated a new password."
  fi
else
  POSTGRES_PASSWORD="$(random_password)"
fi

export DOCKER_HOST

step "Validate operating system and runtime"
INSTALL_STAGE="validate"
[[ -r /etc/os-release ]] || fatal "/etc/os-release was not found."
# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == "debian" ]] || fatal "This installer supports Debian only. Detected: ${ID:-unknown}"
[[ "${VERSION_ID:-}" == "13" || "${VERSION_CODENAME:-}" == "trixie" ]] || fatal "This installer supports Debian 13 Trixie only. Detected: ${PRETTY_NAME:-unknown}"
[[ "$(ps -p 1 -o comm=)" == "systemd" ]] || fatal "This installer requires systemd as PID 1."
ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
  amd64|arm64|armhf|ppc64el) ;;
  *) fatal "Unsupported Debian architecture for Docker Engine: $ARCH" ;;
esac
success "Validated ${PRETTY_NAME:-Debian} on $ARCH"

step "Install prerequisite packages"
INSTALL_STAGE="packages"
apt_run update
apt_run install -y ca-certificates curl gnupg openssl

step "Install Docker Engine from the official Docker repository"
INSTALL_STAGE="docker-install"
remove_pkgs=()
for pkg in docker.io docker-compose docker-doc podman-docker containerd runc; do
  if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
    remove_pkgs+=("$pkg")
  fi
done
if (( ${#remove_pkgs[@]} > 0 )); then
  apt_run remove -y "${remove_pkgs[@]}"
fi

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: trixie
Components: stable
Architectures: $ARCH
Signed-By: /etc/apt/keyrings/docker.asc
EOF
apt_run update
apt_run install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

step "Enable rootful Docker services"
INSTALL_STAGE="rootful-service"
systemctl unmask "$CONTAINERD_SERVICE" "$DOCKER_SERVICE" "$DOCKER_SOCKET_SERVICE" >/dev/null 2>&1 || true
systemctl daemon-reload
systemctl enable --now "$CONTAINERD_SERVICE"
systemctl enable --now "$DOCKER_SOCKET_SERVICE"
systemctl enable --now "$DOCKER_SERVICE"
wait_for_docker
success "Rootful Docker is running through $DOCKER_SERVICE with socket $DOCKER_SOCKET."

step "Configure host bind directory permissions"
INSTALL_STAGE="paths"
install -d -o root -g root -m "$HOST_DIR_MODE" "$HOST_PATH"
install -d -o root -g root -m 0755 "$INSTALL_PATH"
install -d -o root -g root -m 0777 "$DOCKHAND_DATA_PATH"
install -d -o root -g root -m 0777 "$POSTGRES_DATA_PATH"
install -d -o root -g root -m 0700 "$SECRETS_DIR"
chmod "$HOST_DIR_MODE" "$HOST_PATH"
chmod 0777 "$DOCKHAND_DATA_PATH" "$POSTGRES_DATA_PATH"
success "Prepared $HOST_PATH and $INSTALL_PATH."

step "Write installer configuration"
INSTALL_STAGE="config"
install -d -o root -g root -m 0755 "$CONF_DIR"

{
  printf 'SCRIPT_VERSION=%q\n' "$SCRIPT_VERSION"
  printf 'SCRIPT_URL=%q\n' "$SCRIPT_URL"
  printf 'DOCKER_HOST=%q\n' "$DOCKER_HOST"
  printf 'DOCKER_SOCKET=%q\n' "$DOCKER_SOCKET"
  printf 'DOCKER_SERVICE=%q\n' "$DOCKER_SERVICE"
  printf 'HOST_PATH=%q\n' "$HOST_PATH"
  printf 'INSTALL_PATH=%q\n' "$INSTALL_PATH"
  printf 'DOCKHAND_PORT=%q\n' "$DOCKHAND_PORT"
  printf 'COMPOSE_PROJECT_NAME=%q\n' "$COMPOSE_PROJECT_NAME"
  printf 'DOCKHAND_INTERNAL_NETWORK=%q\n' "$DOCKHAND_INTERNAL_NETWORK"
  printf 'CONTAINERS_EXTERNAL_NETWORK=%q\n' "$CONTAINERS_EXTERNAL_NETWORK"
} > "$CONF_FILE"
chmod 0644 "$CONF_FILE"

if is_yes "$INSTALL_SELF_UPDATER"; then
  install_update_helper
fi
success "Wrote $CONF_FILE."

step "Create required Dockhand Docker networks"
INSTALL_STAGE="networks"
ensure_docker_network "$DOCKHAND_INTERNAL_NETWORK" "true"
ensure_docker_network "$CONTAINERS_EXTERNAL_NETWORK" "false"
success "Dockhand will use only $DOCKHAND_INTERNAL_NETWORK and $CONTAINERS_EXTERNAL_NETWORK."

step "Write Dockhand compose files"
INSTALL_STAGE="compose"
cat > "$PASSWORD_FILE" <<EOF
$POSTGRES_PASSWORD
EOF
chmod 0600 "$PASSWORD_FILE"

cat > "$ENV_FILE" <<EOF
COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT_NAME
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
DOCKHAND_INTERNAL_NETWORK=$DOCKHAND_INTERNAL_NETWORK
CONTAINERS_EXTERNAL_NETWORK=$CONTAINERS_EXTERNAL_NETWORK
DOCKER_HOST=$DOCKER_HOST
DOCKER_SOCKET=$DOCKER_SOCKET
EOF
chown root:root "$ENV_FILE"
chmod 0600 "$ENV_FILE"

cat > "$COMPOSE_FILE" <<EOF
services:
  postgres:
    container_name: dockhand-postgres
    image: "$POSTGRES_IMAGE"
    restart: unless-stopped
    environment:
      POSTGRES_USER: dockhand
      POSTGRES_PASSWORD: "${POSTGRES_PASSWORD}"
      POSTGRES_DB: dockhand
    volumes:
      - type: bind
        source: "$POSTGRES_DATA_PATH"
        target: /var/lib/postgresql/data
    networks:
      dockhand-internal: {}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U dockhand -d dockhand"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 20s

  dockhand:
    container_name: dockhand
    image: "$DOCKHAND_IMAGE"
    restart: unless-stopped
    ports:
      - "${DOCKHAND_PORT}:3000"
    environment:
      DATABASE_URL: "postgres://dockhand:${POSTGRES_PASSWORD}@postgres:5432/dockhand"
      DATA_DIR: "$DOCKHAND_DATA_PATH"
      HOST_DATA_DIR: "$DOCKHAND_DATA_PATH"
      DOCKER_HOST: "unix:///var/run/docker.sock"
      COMPOSE_TIMEOUT: "1800"
    volumes:
      - type: bind
        source: "$DOCKER_SOCKET"
        target: /var/run/docker.sock
      - type: bind
        source: "$DOCKHAND_DATA_PATH"
        target: "$DOCKHAND_DATA_PATH"
    networks:
      dockhand-internal: {}
      containers-external: {}
    depends_on:
      postgres:
        condition: service_healthy

networks:
  dockhand-internal:
    name: "$DOCKHAND_INTERNAL_NETWORK"
    external: true
  containers-external:
    name: "$CONTAINERS_EXTERNAL_NETWORK"
    external: true
EOF
chown root:root "$COMPOSE_FILE"
chmod 0640 "$COMPOSE_FILE"
success "Wrote $COMPOSE_FILE."

step "Deploy Dockhand and PostgreSQL"
INSTALL_STAGE="deploy"
docker_compose pull
docker_compose up -d --remove-orphans

step "Verify deployment"
INSTALL_STAGE="verify"
for i in {1..90}; do
  POSTGRES_RUNNING="$(docker_root inspect -f '{{.State.Running}}' dockhand-postgres 2>/dev/null || true)"
  DOCKHAND_RUNNING="$(docker_root inspect -f '{{.State.Running}}' dockhand 2>/dev/null || true)"

  if [[ "$POSTGRES_RUNNING" == "true" && "$DOCKHAND_RUNNING" == "true" ]]; then
    break
  fi

  sleep 2
  if [[ "$i" == "90" ]]; then
    docker_compose ps || true
    docker_compose logs --tail=120 || true
    fatal "Dockhand containers did not reach running state."
  fi
done

prune_container_networks "dockhand-postgres" "$DOCKHAND_INTERNAL_NETWORK"
prune_container_networks "dockhand" "$DOCKHAND_INTERNAL_NETWORK" "$CONTAINERS_EXTERNAL_NETWORK"
docker_root network rm "${COMPOSE_PROJECT_NAME}_default" >/dev/null 2>&1 || true
assert_container_networks "dockhand-postgres" "$DOCKHAND_INTERNAL_NETWORK"
assert_container_networks "dockhand" "$DOCKHAND_INTERNAL_NETWORK" "$CONTAINERS_EXTERNAL_NETWORK"
success "Verified Dockhand network isolation."

if command -v curl >/dev/null 2>&1; then
  for i in {1..60}; do
    if curl -fsS "http://127.0.0.1:${DOCKHAND_PORT}" >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done
fi

SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
[[ -n "$SERVER_IP" ]] || SERVER_IP="SERVER_IP"

success "Installation complete."
cat <<EOF

Dockhand URL:
  http://${SERVER_IP}:${DOCKHAND_PORT}

Rootful Docker:
  Service: $DOCKER_SERVICE
  Socket: $DOCKER_SOCKET
  DOCKER_HOST: $DOCKER_HOST

Dockhand networks:
  PostgreSQL: $DOCKHAND_INTERNAL_NETWORK only
  Dockhand app: $DOCKHAND_INTERNAL_NETWORK and $CONTAINERS_EXTERNAL_NETWORK only
  Internal network: $DOCKHAND_INTERNAL_NETWORK
  External network: $CONTAINERS_EXTERNAL_NETWORK

Run Docker manually as root:
  sudo docker info
  sudo DOCKER_HOST=$DOCKER_HOST docker compose -f $COMPOSE_FILE ps

Manage services:
  systemctl status $DOCKER_SERVICE
  systemctl status $DOCKER_SOCKET_SERVICE
  journalctl -u $DOCKER_SERVICE -n 100 --no-pager
  cd $INSTALL_PATH && DOCKER_HOST=$DOCKER_HOST docker compose ps

Files:
  Compose file: $COMPOSE_FILE
  Dockhand data: $DOCKHAND_DATA_PATH
  PostgreSQL data: $POSTGRES_DATA_PATH
  PostgreSQL password: $PASSWORD_FILE
  Installer config: $CONF_FILE
  Installer log: $LOG_FILE

Self-update:
  $UPDATE_HELPER

EOF
