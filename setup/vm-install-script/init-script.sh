#!/bin/bash
# ==============================================================================
# Bootstrap serveur Ubuntu 24.04+ (lab DevOps / hub)
#
# CE QUE CE SCRIPT INSTALLE
# ------------------------------------------------------------------------------
# Base & shell
#   - apt à jour, needrestart auto, prompt bash coloré
#   - curl, wget, unzip, zip, ca-certificates, gnupg, lsb-release
#   - vim, nano, tree, htop, tmux, jq, yq (via snap si dispo / sinon skip)
#
# Git
#   - git
#
# Réseau / debug
#   - net-tools, iproute2, dnsutils, traceroute, mtr-tiny
#   - nmap, tcpdump, netcat-openbsd, iputils-ping, traceroute
#   - openssh-client
#
# Docker
#   - Docker Engine (CE) + containerd + docker compose plugin
#   - service docker enabled
#   - utilisateur courant ajouté au groupe docker (si non-root)
#
# Java / build
#   - OpenJDK 21 (ou plus récent si dispo)
#   - Maven
#
# Node.js
#   - Node.js 24 LTS (repo NodeSource, npm inclus) — pas le paquet Ubuntu (18 sans npm)
#
# Utilitaires DevOps
#   - python3, python3-pip, python3-venv
#   - make, build-essential
#   - software-properties-common
# ==============================================================================

set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Exécute ce script en root (sudo)."
  exit 1
fi

. /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "Script prévu pour Ubuntu (détecté: ${ID:-inconnu})."
  exit 1
fi
MAJOR="${VERSION_ID%%.*}"
if [[ "${MAJOR}" -lt 24 ]]; then
  echo "Ubuntu 24.04+ requis (détecté: ${VERSION_ID})."
  exit 1
fi

echo ".........----------------#################._.-.-INSTALL-.-._.#################----------------........."
echo "Ubuntu ${VERSION_ID} — bootstrap DevOps (sans K8s / sans Jenkins)"

# Prompt bash coloré
PS1='\[\e[01;36m\]\u\[\e[01;37m\]@\[\e[01;33m\]\H\[\e[01;37m\]:\[\e[01;32m\]\w\[\e[01;37m\]\$\[\033[0;37m\] '
grep -q "force_color_prompt=yes" ~/.bashrc 2>/dev/null || sed -i '1s/^/force_color_prompt=yes\n/' ~/.bashrc
grep -qF "$PS1" ~/.bashrc 2>/dev/null || echo "PS1='$PS1'" >> ~/.bashrc

# Ne pas demander de redémarrer les services après apt
if [[ -f /etc/needrestart/needrestart.conf ]]; then
  sed -i "s/#\$nrconf{restart} = 'i'/\$nrconf{restart} = 'a'/" /etc/needrestart/needrestart.conf || true
fi

export DEBIAN_FRONTEND=noninteractive

# Nettoie toute config Docker APT conflictuelle (gpg vs asc, list vs sources)
echo ".........----------------#################._.-.-CLEAN DOCKER APT-.-._.#################----------------........."
rm -f /etc/apt/sources.list.d/docker.list \
      /etc/apt/sources.list.d/docker.sources \
      /etc/apt/keyrings/docker.gpg \
      /etc/apt/keyrings/docker.asc
# Entrées Docker éventuelles dans sources.list
sed -i '/download\.docker\.com\/linux\/ubuntu/d' /etc/apt/sources.list 2>/dev/null || true
# Fichiers *docker* restants dans sources.list.d
find /etc/apt/sources.list.d -maxdepth 1 -type f \( -iname '*docker*' \) -delete 2>/dev/null || true

echo ".........----------------#################._.-.-APT BASE-.-._.#################----------------........."
apt-get update -y
apt-get upgrade -y
apt-get autoremove -y
apt-get install -y \
  ca-certificates \
  curl \
  wget \
  gnupg \
  lsb-release \
  apt-transport-https \
  software-properties-common \
  git \
  vim \
  nano \
  tree \
  htop \
  tmux \
  jq \
  unzip \
  zip \
  make \
  build-essential \
  python3 \
  python3-pip \
  python3-venv \
  openssh-client \
  net-tools \
  iproute2 \
  dnsutils \
  iputils-ping \
  traceroute \
  mtr-tiny \
  nmap \
  tcpdump \
  netcat-openbsd

# yq (optionnel)
if command -v snap >/dev/null 2>&1; then
  snap install yq || true
fi

echo ".........----------------#################._.-.-DOCKER-.-._.#################----------------........."
# Repo officiel Docker (une seule clé : docker.asc)
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF

systemctl daemon-reload
systemctl enable --now docker

# Ajoute l'utilisateur sudo / login au groupe docker si possible
TARGET_USER="${SUDO_USER:-}"
if [[ -n "${TARGET_USER}" && "${TARGET_USER}" != "root" ]]; then
  usermod -aG docker "${TARGET_USER}"
  echo "Utilisateur ${TARGET_USER} ajouté au groupe docker (relogin requis)."
fi

docker --version
docker compose version || true

echo ".........----------------#################._.-.-JAVA 21 + MAVEN-.-._.#################----------------........."
apt-get install -y openjdk-21-jdk maven
java -version
mvn -v

echo ".........----------------#################._.-.-NODE.JS 24 + NPM-.-._.#################----------------........."
# Ubuntu 24 : nodejs 18.x sans npm. On le remplace par Node 24 LTS NodeSource (npm inclus).
apt-get remove --purge -y nodejs npm libnode-dev 2>/dev/null || true
apt-get autoremove -y || true
rm -f /etc/apt/sources.list.d/nodesource.list \
      /etc/apt/sources.list.d/nodesource.sources \
      /etc/apt/keyrings/nodesource.gpg \
      /usr/share/keyrings/nodesource.gpg

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
  | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
chmod a+r /etc/apt/keyrings/nodesource.gpg

NODE_MAJOR=24
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
  > /etc/apt/sources.list.d/nodesource.list
cat > /etc/apt/preferences.d/nodesource <<'EOF'
Package: nodejs
Pin: origin deb.nodesource.com
Pin-Priority: 1001
EOF

apt-get update -y
apt-get install -y nodejs
hash -r
node -v
npm -v

echo ".........----------------#################._.-.-COMPLETED-.-._.#################----------------........."
echo "OK — Docker, Git, Java 21, Maven, Node.js 24, npm, outils réseau / DevOps installés."
