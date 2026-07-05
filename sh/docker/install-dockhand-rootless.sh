#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "ERROR on line $LINENO"; exit 1' ERR

if [[ $EUID -ne 0 ]]; then
  echo "Run as root."
  exit 1
fi

ask() {
  local prompt="$1"
  local default="$2"
  local value
  read -rp "$prompt [$default]: " value
  echo "${value:-$default}"
}

echo "Dockhand rootless Docker installer for Debian 13"

DOCKER_USER="$(ask "Rootless Docker Linux user" "docker")"
DOCKER_UID="$(ask "User UID" "1001")"
DOCKER_GID="$(ask "User GID" "1001")"
SUBUID_START="$(ask "subuid/subgid start" "100000")"
SUBUID_COUNT="$(ask "subuid/subgid count" "65536")"
HOST_PATH="$(ask "Default Docker host data path" "/dockershare/containers")"
INSTALL_PATH="$(ask "Dockhand install path" "$HOST_PATH/dockhand")"
DOCKHAND_PORT="$(ask "Dockhand web port" "3000")"
POSTGRES_PASSWORD="$(openssl rand -base64 36 | tr -d '=+/' | cut -c1-32)"

if ! grep -qi "trixie" /etc/os-release; then
  echo "This script is intended for Debian 13 Trixie."
  exit 1
fi

apt-get update
apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  uidmap \
  dbus-user-session \
  slirp4netns \
  fuse-overlayfs \
  openssl \
  sudo

install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/debian/gpg \
  -o /etc/apt/keyrings/docker.asc

chmod a+r /etc/apt/keyrings/docker.asc

cat >/etc/apt/sources.list.d/docker.sources <<'EOF'
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: trixie
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt-get update
apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin \
  docker-ce-rootless-extras

systemctl disable --now docker.service docker.socket || true

if ! getent group "$DOCKER_USER" >/dev/null; then
  groupadd -g "$DOCKER_GID" "$DOCKER_USER"
fi

if ! id "$DOCKER_USER" >/dev/null 2>&1; then
  useradd -m -u "$DOCKER_UID" -g "$DOCKER_USER" -s /bin/bash "$DOCKER_USER"
fi

sed -i "\|^${DOCKER_USER}:|d" /etc/subuid /etc/subgid
echo "${DOCKER_USER}:${SUBUID_START}:${SUBUID_COUNT}" >> /etc/subuid
echo "${DOCKER_USER}:${SUBUID_START}:${SUBUID_COUNT}" >> /etc/subgid

loginctl enable-linger "$DOCKER_USER"

mkdir -p "$INSTALL_PATH"/{data,postgres}
chown -R "$DOCKER_USER:$DOCKER_USER" "$HOST_PATH"
chmod -R u+rwX,g+rwX "$HOST_PATH"

sudo -iu "$DOCKER_USER" bash <<'EOSU'
set -Eeuo pipefail

export XDG_RUNTIME_DIR="/run/user/$(id -u)"

if ! systemctl --user is-active dbus >/dev/null 2>&1; then
  systemctl --user start dbus || true
fi

dockerd-rootless-setuptool.sh install --force

systemctl --user enable docker
systemctl --user restart docker

for i in {1..30}; do
  if docker info >/dev/null 2>&1; then
    exit 0
  fi
  sleep 1
done

echo "Rootless Docker did not become ready."
exit 1
EOSU

DOCKER_REAL_UID="$(id -u "$DOCKER_USER")"
DOCKER_HOST="unix:///run/user/${DOCKER_REAL_UID}/docker.sock"

cat > "$INSTALL_PATH/docker-compose.yml" <<EOF
services:
  postgres:
    container_name: dockhand-postgres
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: dockhand
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: dockhand
    volumes:
      - ${INSTALL_PATH}/postgres:/var/lib/postgresql/data

  dockhand:
    container_name: dockhand
    image: fnsys/dockhand:latest
    restart: unless-stopped
    ports:
      - "${DOCKHAND_PORT}:3000"
    environment:
      DATABASE_URL: postgres://dockhand:${POSTGRES_PASSWORD}@postgres:5432/dockhand
      DATA_DIR: ${INSTALL_PATH}/data
    volumes:
      - /run/user/${DOCKER_REAL_UID}/docker.sock:/var/run/docker.sock
      - ${INSTALL_PATH}/data:${INSTALL_PATH}/data
    depends_on:
      - postgres
EOF

chown -R "$DOCKER_USER:$DOCKER_USER" "$INSTALL_PATH"

sudo -iu "$DOCKER_USER" bash <<EOF
set -Eeuo pipefail

export XDG_RUNTIME_DIR="/run/user/${DOCKER_REAL_UID}"
export DOCKER_HOST="${DOCKER_HOST}"

cd "$INSTALL_PATH"
docker compose up -d
EOF

cat <<EOF

Install complete.

Dockhand URL:
http://$(hostname -I | awk '{print $1}'):${DOCKHAND_PORT}

Run Docker as:
sudo -iu ${DOCKER_USER}
export DOCKER_HOST=${DOCKER_HOST}

Compose file:
${INSTALL_PATH}/docker-compose.yml

PostgreSQL password:
${POSTGRES_PASSWORD}

EOF
