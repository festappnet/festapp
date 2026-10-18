#!/usr/bin/env bash
set -euo pipefail

readonly DOCKER_VERSION=29.7.2
readonly COMPOSE_VERSION=5.5.0
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ "$(id -u)" == "0" ]] || { echo "bootstrap-host must run as root" >&2; exit 1; }
[[ "$(uname -m)" == "aarch64" ]] || { echo "expected an ARM64 host" >&2; exit 1; }
. /etc/os-release
[[ "$VERSION_ID" == "26.04" ]] || { echo "expected Ubuntu 26.04" >&2; exit 1; }

apt-get update -qq
apt-get install -y -qq ca-certificates curl iproute2 jq nodejs ripgrep
install -d -m 0755 /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod 0644 /etc/apt/keyrings/docker.asc
fi
install -o root -g root -m 0644 "$SCRIPT_DIR/docker.sources" /etc/apt/sources.list.d/docker.sources
apt-get update -qq

docker_package="$(apt-cache madison docker-ce | awk -v wanted="$DOCKER_VERSION" '$3 ~ wanted && !found {found=$3} END {print found}')"
compose_package="$(apt-cache madison docker-compose-plugin | awk -v wanted="$COMPOSE_VERSION" '$3 ~ wanted && !found {found=$3} END {print found}')"
[[ -n "$docker_package" ]] || { echo "Docker $DOCKER_VERSION is unavailable" >&2; exit 1; }
[[ -n "$compose_package" ]] || { echo "Compose $COMPOSE_VERSION is unavailable" >&2; exit 1; }

apt-get install -y -qq \
  "docker-ce=$docker_package" \
  "docker-ce-cli=$docker_package" \
  containerd.io docker-buildx-plugin \
  "docker-compose-plugin=$compose_package"
install -o root -g root -m 0644 "$SCRIPT_DIR/docker-daemon.json" /etc/docker/daemon.json
systemctl enable --now docker
systemctl reload docker

docker version --format 'docker server={{.Server.Version}} architecture={{.Server.Arch}}'
docker compose version
