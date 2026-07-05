#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="install-dockhand-rootless"
SCRIPT_VERSION="2026.07.05-r4"
DEFAULT_SCRIPT_URL="https://raw.githubusercontent.com/paulkakell/Pauls_Big_Script_Repo/main/sh/docker/install-dockhand-rootless.sh"
SCRIPT_URL="${SCRIPT_URL:-$DEFAULT_SCRIPT_URL}"
LOCAL_SCRIPT="/usr/local/sbin/install-dockhand-rootless"
UPDATE_HELPER="/usr/local/bin/dockhand-installer-update"
CONF_DIR="/etc/dockhand-rootless-installer"
CONF_FILE="$CONF_DIR/install.conf"
LOG_DIR="/var/log"
LOG_FILE="$LOG_DIR/dockhand-rootless-install-$(date +%Y%m%d-%H%M%S).log"

USE_DEFAULTS="no"
ROLLBACK_ON_FAIL="unset"
UPDATE_SELF="no"
SHOW_HELP="no"
INSTALL_STAGE="start"
TOTAL_STEPS=13
CURRENT_STEP=0

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
  bash install-dockhand-rootless.sh [options]

Options:
  -y, --yes, --defaults       Use defaults and do not prompt.
  --script-url URL            Raw GitHub URL used by the self-update helper.
  --rollback                  Roll back the Dockhand compose stack if deployment fails.
  --no-rollback               Do not roll back on deployment failure.
  --update-self               Download this installer from SCRIPT_URL into $LOCAL_SCRIPT.
  -h, --help                  Show this help.

Environment overrides:
  DOCKER_USER                 Default: docker
  DOCKER_UID                  Default: 1001
  DOCKER_GID                  Default: 1001
  SUBUID_START                Default: 100000
  SUBUID_COUNT                Default: 65536
  HOST_PATH                   Default: /dockershare/containers
  INSTALL_PATH                Default: HOST_PATH/dockhand
  DOCKHAND_PORT               Default: 3000
  DOCKHAND_IMAGE              Default: fnsys/dockhand:latest
  POSTGRES_IMAGE              Default: postgres:16-alpine
  POSTGRES_PASSWORD           Default: generated
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

quote_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

validate_username() {
  [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || fatal "Invalid Linux username: $1"
  [[ "$1" != "root" ]] || fatal "Do not use root as the rootless Docker user."
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
  [[ -n "${DOCKER_USER:-}" && -n "${DOCKER_HOST:-}" ]] || return 0

  warn "Rolling back Dockhand compose stack. Persistent files are left on disk."
  as_docker_user bash -lc 'cd "$1" && docker compose down --remove-orphans || true' _ "$INSTALL_PATH" || true
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

as_docker_user() {
  sudo -u "$DOCKER_USER" -H -- env \
    HOME="$DOCKER_HOME" \
    USER="$DOCKER_USER" \
    LOGNAME="$DOCKER_USER" \
    XDG_RUNTIME_DIR="$RUNTIME_DIR" \
    DOCKER_HOST="$DOCKER_HOST" \
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    "$@"
}

wait_for_rootless_docker() {
  local i
  for i in {1..90}; do
    if as_docker_user docker info >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  systemctl --no-pager --full status "$ROOTLESS_SERVICE" || true
  journalctl -u "$ROOTLESS_SERVICE" --no-pager -n 120 || true
  fatal "Rootless Docker did not become ready."
}

write_user_shell_exports() {
  local bashrc profile marker_begin marker_end
  bashrc="$DOCKER_HOME/.bashrc"
  profile="$DOCKER_HOME/.profile"
  marker_begin="# BEGIN dockhand-rootless-docker"
  marker_end="# END dockhand-rootless-docker"
  touch "$bashrc" "$profile"
  chown "$DOCKER_USER:$DOCKER_GROUP" "$bashrc" "$profile"

  for file in "$bashrc" "$profile"; do
    sed -i "/$marker_begin/,/$marker_end/d" "$file"
    cat >> "$file" <<EOF
$marker_begin
export XDG_RUNTIME_DIR="$RUNTIME_DIR"
export DOCKER_HOST="$DOCKER_HOST"
export PATH="/usr/bin:\$PATH"
$marker_end
EOF
    chown "$DOCKER_USER:$DOCKER_GROUP" "$file"
  done
}

if [[ "$UPDATE_SELF" == "yes" ]]; then
  self_update
  exit 0
fi

printf '%s%s %s%s\n' "$C_BOLD" "$SCRIPT_NAME" "$SCRIPT_VERSION" "$C_RESET"
printf 'Log file: %s\n' "$LOG_FILE"

step "Collect installation settings"
DOCKER_USER="$(ask "Rootless Docker Linux user" "${DOCKER_USER:-docker}")"
DOCKER_GROUP="$DOCKER_USER"
DOCKER_UID="$(ask "User UID" "${DOCKER_UID:-1001}")"
DOCKER_GID="$(ask "User GID" "${DOCKER_GID:-1001}")"
SUBUID_START="$(ask "subuid/subgid start" "${SUBUID_START:-100000}")"
SUBUID_COUNT="$(ask "subuid/subgid count" "${SUBUID_COUNT:-65536}")"
HOST_PATH="$(ask "Default Docker host data path" "${HOST_PATH:-/dockershare/containers}")"
INSTALL_PATH_DEFAULT="${INSTALL_PATH:-$HOST_PATH/dockhand}"
INSTALL_PATH="$(ask "Dockhand install path" "$INSTALL_PATH_DEFAULT")"
DOCKHAND_PORT="$(ask "Dockhand web port" "${DOCKHAND_PORT:-3000}")"
HOST_DIR_MODE="$(ask "Host bind directory mode" "${HOST_DIR_MODE:-1777}")"
DOCKHAND_IMAGE="$(ask "Dockhand image" "${DOCKHAND_IMAGE:-fnsys/dockhand:latest}")"
POSTGRES_IMAGE="$(ask "PostgreSQL image" "${POSTGRES_IMAGE:-postgres:16-alpine}")"
COMPOSE_PROJECT_NAME="$(ask "Compose project name" "${COMPOSE_PROJECT_NAME:-dockhand}")"
INSTALL_SELF_UPDATER="$(ask_yes_no "Install local self-update helper" "yes")"

if [[ "$ROLLBACK_ON_FAIL" == "unset" ]]; then
  ROLLBACK_ON_FAIL="$(ask_yes_no "Rollback Dockhand stack if deployment fails" "yes")"
fi

POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(random_password)}"

validate_username "$DOCKER_USER"
validate_numeric "User UID" "$DOCKER_UID"
validate_numeric "User GID" "$DOCKER_GID"
validate_numeric "subuid/subgid start" "$SUBUID_START"
validate_numeric "subuid/subgid count" "$SUBUID_COUNT"
validate_abs_path "Default Docker host data path" "$HOST_PATH"
validate_abs_path "Dockhand install path" "$INSTALL_PATH"
validate_port "$DOCKHAND_PORT"
[[ "$HOST_DIR_MODE" =~ ^[0-7]{3,4}$ ]] || fatal "Host bind directory mode must be an octal mode, such as 1777 or 0777."
[[ "$COMPOSE_PROJECT_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || fatal "Compose project name contains invalid characters."
(( SUBUID_COUNT >= 65536 )) || fatal "subuid/subgid count must be at least 65536."

if (( DOCKHAND_PORT < 1024 )); then
  LOW_PORTS="$(ask_yes_no "Enable unprivileged binding for ports below 1024" "yes")"
else
  LOW_PORTS="no"
fi

DOCKHAND_DATA_PATH="$INSTALL_PATH/data"
POSTGRES_DATA_PATH="$INSTALL_PATH/postgres"
SECRETS_DIR="$INSTALL_PATH/secrets"
ENV_FILE="$INSTALL_PATH/.env"
COMPOSE_FILE="$INSTALL_PATH/docker-compose.yml"
PASSWORD_FILE="$SECRETS_DIR/postgres-password.txt"

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
apt_run install -y ca-certificates curl gnupg uidmap dbus-user-session slirp4netns fuse-overlayfs openssl sudo

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
apt_run install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras

step "Disable rootful Docker services"
INSTALL_STAGE="disable-rootful"
systemctl disable --now docker.service docker.socket >/dev/null 2>&1 || true
systemctl disable --now containerd.service >/dev/null 2>&1 || true
rm -f /var/run/docker.sock
success "Rootful docker.service and docker.socket are disabled."

step "Create and configure the rootless Docker user"
INSTALL_STAGE="user"
if getent group "$DOCKER_GROUP" >/dev/null; then
  EXISTING_GID="$(getent group "$DOCKER_GROUP" | cut -d: -f3)"
  if [[ "$EXISTING_GID" != "$DOCKER_GID" ]]; then
    warn "Group $DOCKER_GROUP already exists with GID $EXISTING_GID. Using existing GID instead of requested GID $DOCKER_GID."
    DOCKER_GID="$EXISTING_GID"
  fi
else
  if getent group "$DOCKER_GID" >/dev/null; then
    fatal "GID $DOCKER_GID already belongs to group $(getent group "$DOCKER_GID" | cut -d: -f1). Choose another GID."
  fi
  groupadd -g "$DOCKER_GID" "$DOCKER_GROUP"
fi

if id "$DOCKER_USER" >/dev/null 2>&1; then
  EXISTING_UID="$(id -u "$DOCKER_USER")"
  if [[ "$EXISTING_UID" != "$DOCKER_UID" ]]; then
    warn "User $DOCKER_USER already exists with UID $EXISTING_UID. Using existing UID."
    DOCKER_UID="$EXISTING_UID"
  fi
  usermod -g "$DOCKER_GROUP" -s /bin/bash "$DOCKER_USER"
else
  if getent passwd "$DOCKER_UID" >/dev/null; then
    fatal "UID $DOCKER_UID already belongs to user $(getent passwd "$DOCKER_UID" | cut -d: -f1). Choose another UID."
  fi
  useradd -m -u "$DOCKER_UID" -g "$DOCKER_GROUP" -s /bin/bash "$DOCKER_USER"
fi

DOCKER_REAL_UID="$(id -u "$DOCKER_USER")"
DOCKER_REAL_GID="$(id -g "$DOCKER_USER")"
DOCKER_HOME="$(getent passwd "$DOCKER_USER" | cut -d: -f6)"
RUNTIME_DIR="/run/user/$DOCKER_REAL_UID"
DOCKER_SOCKET="$RUNTIME_DIR/docker.sock"
DOCKER_HOST="unix://$DOCKER_SOCKET"
ROOTLESS_SERVICE="docker-rootless-$DOCKER_USER.service"

if (( DOCKER_REAL_UID >= SUBUID_START && DOCKER_REAL_UID < SUBUID_START + SUBUID_COUNT )); then
  fatal "The real user UID overlaps the subordinate UID range. Choose a different UID or subuid start."
fi
if (( DOCKER_REAL_GID >= SUBUID_START && DOCKER_REAL_GID < SUBUID_START + SUBUID_COUNT )); then
  fatal "The real user GID overlaps the subordinate GID range. Choose a different GID or subgid start."
fi

sed -i "\|^${DOCKER_USER}:|d" /etc/subuid /etc/subgid
echo "${DOCKER_USER}:${SUBUID_START}:${SUBUID_COUNT}" >> /etc/subuid
echo "${DOCKER_USER}:${SUBUID_START}:${SUBUID_COUNT}" >> /etc/subgid
install -d -o "$DOCKER_USER" -g "$DOCKER_GROUP" -m 0700 "$RUNTIME_DIR"
loginctl enable-linger "$DOCKER_USER" >/dev/null 2>&1 || true
write_user_shell_exports
success "Configured $DOCKER_USER with subordinate UID/GID range ${SUBUID_START}:${SUBUID_COUNT}."

step "Configure host bind directory permissions"
INSTALL_STAGE="paths"
install -d -o "$DOCKER_USER" -g "$DOCKER_GROUP" -m "$HOST_DIR_MODE" "$HOST_PATH"
install -d -o "$DOCKER_USER" -g "$DOCKER_GROUP" -m 0775 "$INSTALL_PATH"
install -d -o "$DOCKER_USER" -g "$DOCKER_GROUP" -m 0777 "$DOCKHAND_DATA_PATH"
install -d -o "$DOCKER_USER" -g "$DOCKER_GROUP" -m 0777 "$POSTGRES_DATA_PATH"
install -d -o root -g root -m 0700 "$SECRETS_DIR"
chmod "$HOST_DIR_MODE" "$HOST_PATH"
chmod 0777 "$DOCKHAND_DATA_PATH" "$POSTGRES_DATA_PATH"
success "Prepared $HOST_PATH and $INSTALL_PATH."

if is_yes "$LOW_PORTS"; then
  step "Enable low port binding for rootless containers"
  INSTALL_STAGE="low-ports"
  cat >/etc/sysctl.d/99-rootless-docker-low-ports.conf <<'EOF'
net.ipv4.ip_unprivileged_port_start=0
EOF
  sysctl --system >/dev/null
  success "Rootless containers may publish ports below 1024."
else
  step "Skip low port binding"
  info "Dockhand is using port $DOCKHAND_PORT, so no low-port sysctl change is required."
fi

step "Create system service for the rootless Docker daemon"
INSTALL_STAGE="rootless-service"
cat > "/etc/systemd/system/$ROOTLESS_SERVICE" <<EOF
[Unit]
Description=Rootless Docker daemon for $DOCKER_USER
Documentation=https://docs.docker.com/engine/security/rootless/
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=120
StartLimitBurst=10

[Service]
Type=simple
User=$DOCKER_USER
Group=$DOCKER_GROUP
Environment=HOME=$DOCKER_HOME
Environment=USER=$DOCKER_USER
Environment=LOGNAME=$DOCKER_USER
Environment=XDG_RUNTIME_DIR=$RUNTIME_DIR
Environment=DOCKER_HOST=$DOCKER_HOST
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=DOCKERD_ROOTLESS_ROOTLESSKIT_NET=slirp4netns
Environment=DOCKERD_ROOTLESS_ROOTLESSKIT_PORT_DRIVER=builtin
ExecStartPre=+/usr/bin/install -d -o $DOCKER_USER -g $DOCKER_GROUP -m 0700 $RUNTIME_DIR
ExecStartPre=+/bin/rm -f $DOCKER_SOCKET
ExecStart=/usr/bin/dockerd-rootless.sh --host=$DOCKER_HOST
ExecStopPost=+/bin/rm -f $DOCKER_SOCKET
Restart=always
RestartSec=3
TimeoutStartSec=120
Delegate=yes
KillMode=mixed
LimitNOFILE=infinity
LimitNPROC=infinity
TasksMax=infinity

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now "$ROOTLESS_SERVICE"
wait_for_rootless_docker
success "Rootless Docker is running through $ROOTLESS_SERVICE."

step "Create Docker context and installer configuration"
INSTALL_STAGE="config"
install -d -o root -g root -m 0755 "$CONF_DIR"
as_docker_user docker context rm -f rootless >/dev/null 2>&1 || true
as_docker_user docker context create rootless --description "Rootless Docker for $DOCKER_USER" --docker "host=$DOCKER_HOST" >/dev/null
as_docker_user docker context use rootless >/dev/null 2>&1 || true

{
  printf 'SCRIPT_VERSION=%q\n' "$SCRIPT_VERSION"
  printf 'SCRIPT_URL=%q\n' "$SCRIPT_URL"
  printf 'DOCKER_USER=%q\n' "$DOCKER_USER"
  printf 'DOCKER_GROUP=%q\n' "$DOCKER_GROUP"
  printf 'DOCKER_UID=%q\n' "$DOCKER_REAL_UID"
  printf 'DOCKER_GID=%q\n' "$DOCKER_REAL_GID"
  printf 'DOCKER_HOST=%q\n' "$DOCKER_HOST"
  printf 'ROOTLESS_SERVICE=%q\n' "$ROOTLESS_SERVICE"
  printf 'HOST_PATH=%q\n' "$HOST_PATH"
  printf 'INSTALL_PATH=%q\n' "$INSTALL_PATH"
  printf 'DOCKHAND_PORT=%q\n' "$DOCKHAND_PORT"
  printf 'COMPOSE_PROJECT_NAME=%q\n' "$COMPOSE_PROJECT_NAME"
} > "$CONF_FILE"
chmod 0644 "$CONF_FILE"

if is_yes "$INSTALL_SELF_UPDATER"; then
  install_update_helper
fi
success "Wrote $CONF_FILE."

step "Write Dockhand compose files"
INSTALL_STAGE="compose"
cat > "$PASSWORD_FILE" <<EOF
$POSTGRES_PASSWORD
EOF
chmod 0600 "$PASSWORD_FILE"

cat > "$ENV_FILE" <<EOF
COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT_NAME
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
EOF
chown "$DOCKER_USER:$DOCKER_GROUP" "$ENV_FILE"
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
    depends_on:
      postgres:
        condition: service_healthy
EOF
chown "$DOCKER_USER:$DOCKER_GROUP" "$COMPOSE_FILE"
chmod 0640 "$COMPOSE_FILE"
success "Wrote $COMPOSE_FILE."

step "Deploy Dockhand and PostgreSQL"
INSTALL_STAGE="deploy"
as_docker_user bash -lc 'cd "$1" && docker compose pull && docker compose up -d' _ "$INSTALL_PATH"

step "Verify deployment"
INSTALL_STAGE="verify"
for i in {1..90}; do
  if as_docker_user docker inspect -f '{{.State.Running}}' dockhand-postgres >/dev/null 2>&1 && \
     as_docker_user docker inspect -f '{{.State.Running}}' dockhand >/dev/null 2>&1; then
    break
  fi
  sleep 2
  if [[ "$i" == "90" ]]; then
    as_docker_user bash -lc 'cd "$1" && docker compose ps && docker compose logs --tail=120' _ "$INSTALL_PATH" || true
    fatal "Dockhand containers did not reach running state."
  fi
done

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

Rootless Docker:
  Service: $ROOTLESS_SERVICE
  User: $DOCKER_USER
  Socket: $DOCKER_SOCKET
  DOCKER_HOST: $DOCKER_HOST

Run Docker manually as the rootless user:
  sudo -iu $DOCKER_USER
  docker info

Manage services:
  systemctl status $ROOTLESS_SERVICE
  journalctl -u $ROOTLESS_SERVICE -n 100 --no-pager
  cd $INSTALL_PATH && sudo -u $DOCKER_USER -H env DOCKER_HOST=$DOCKER_HOST docker compose ps

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
