#!/bin/bash
# ==============================================================================
# Installation Jenkins LTS — Ubuntu 24.04+
#
# Prérequis : init-script.sh (Docker, Git, OpenJDK 21).
# Ce script installe Java 21 s'il est absent.
#
# CE QUE CE SCRIPT INSTALLE
# ------------------------------------------------------------------------------
#   - OpenJDK 21 (si manquant)
#   - Jenkins LTS (repo officiel pkg.jenkins.io)
#   - service systemd jenkins enabled (port 8080)
#   - utilisateur jenkins ajouté au groupe docker
#   - plugins lab (latest, IDs issus de setup/jenkins-plugins/plugins.txt) :
#       git, workflow-aggregator, docker-workflow, blueocean,
#       sonar, jacoco, slack, performance, pitmutation,
#       dependency-check-jenkins-plugin, kubernetes-cli
#
# Accès : http://<ip>:8080  (ou jenkins.santu.io si reverse-proxy)
# Mot de passe initial : /var/lib/jenkins/secrets/initialAdminPassword
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

export DEBIAN_FRONTEND=noninteractive
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_FILE="${SCRIPT_DIR}/../jenkins-plugins/plugins.txt"

echo ".........----------------#################._.-.-JENKINS-.-._.#################----------------........."

if ! command -v java >/dev/null 2>&1; then
  echo "Java absent — installation OpenJDK 21..."
  apt-get update -y
  apt-get install -y openjdk-21-jdk
fi
java -version

echo ".........----------------#################._.-.-REPO JENKINS LTS-.-._.#################----------------........."
apt-get update -y
apt-get install -y curl ca-certificates gnupg fontconfig

# Clé 2026 (LTS ≥ 2.541.1) — l'ancienne jenkins.io-2023.key donne NO_PUBKEY 7198F4B714ABFC68
install -m 0755 -d /etc/apt/keyrings /usr/share/keyrings
rm -f /etc/apt/keyrings/jenkins-keyring.asc \
      /usr/share/keyrings/jenkins-keyring.asc \
      /etc/apt/sources.list.d/jenkins.list
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key \
  -o /etc/apt/keyrings/jenkins-keyring.asc
chmod a+r /etc/apt/keyrings/jenkins-keyring.asc
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  > /etc/apt/sources.list.d/jenkins.list

apt-get update -y
apt-get install -y jenkins

# Java 21 explicite pour le service
install -d /etc/systemd/system/jenkins.service.d
cat > /etc/systemd/system/jenkins.service.d/override.conf <<'EOF'
[Service]
Environment="JAVA_OPTS=-Djava.awt.headless=true"
EOF

if getent group docker >/dev/null 2>&1; then
  usermod -aG docker jenkins
  echo "Utilisateur jenkins ajouté au groupe docker."
else
  echo "Groupe docker introuvable — lance d'abord init-script.sh (Docker)."
fi

echo ".........----------------#################._.-.-PLUGINS-.-._.#################----------------........."
# IDs du lab ; versions épinglées du plugins.txt ignorées (trop anciennes pour un LTS actuel)
PLUGINS=(
  git
  workflow-aggregator
  docker-workflow
  blueocean
  sonar
  jacoco
  slack
  performance
  pitmutation
  dependency-check-jenkins-plugin
  kubernetes-cli
)

if [[ -f "${PLUGIN_FILE}" ]]; then
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
    name="${line%%@*}"
    name="${name%%[[:space:]]*}"
    [[ -n "${name}" ]] && PLUGINS+=("${name}")
  done < "${PLUGIN_FILE}"
fi

# Déduplique
mapfile -t PLUGINS < <(printf '%s\n' "${PLUGINS[@]}" | awk 'NF && !seen[$0]++')

if command -v jenkins-plugin-cli >/dev/null 2>&1; then
  jenkins-plugin-cli --plugins "${PLUGINS[@]}" --plugin-download-directory /var/lib/jenkins/plugins
  chown -R jenkins:jenkins /var/lib/jenkins/plugins
else
  echo "jenkins-plugin-cli absent — plugins à installer depuis l'UI."
fi

systemctl daemon-reload
systemctl enable --now jenkins

echo "Attente du démarrage Jenkins (port 8080)..."
for _ in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:8080/login >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

echo ".........----------------#################._.-.-COMPLETED-.-._.#################----------------........."
systemctl --no-pager --full status jenkins | sed -n '1,12p' || true
echo
echo "Jenkins : http://$(hostname -I | awk '{print $1}'):8080"
if [[ -f /var/lib/jenkins/secrets/initialAdminPassword ]]; then
  echo "Mot de passe initial admin :"
  cat /var/lib/jenkins/secrets/initialAdminPassword
else
  echo "Fichier initialAdminPassword absent (setup wizard déjà passé ?)."
fi
