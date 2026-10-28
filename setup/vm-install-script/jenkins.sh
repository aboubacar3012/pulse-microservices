#!/bin/bash
# ==============================================================================
# Installation Jenkins LTS (Docker) — Ubuntu 24.04+
#
# Prérequis : Docker doit être installé sur le serveur.
#
# CE QUE CE SCRIPT INSTALLE
# ------------------------------------------------------------------------------
#   - Docker (vérifie qu'il est présent)
#   - Jenkins LTS via conteneur Docker (port 8080, port 50000 pour les agents)
#   - Bind mount du répertoire /var/jenkins_home sur l'hôte (/opt/jenkins_home)
#   - Accès au socket Docker depuis le conteneur (DooD)
#   - Plugins lab installés automatiquement via jenkins-plugin-cli
#
# Accès : http://<ip>:8080
# Mot de passe initial : /opt/jenkins_home/secrets/initialAdminPassword
# ==============================================================================

set -euo pipefail

# 1. Vérification que le script est lancé en root
if [[ "$(id -u)" -ne 0 ]]; then
  echo "Exécute ce script en root (sudo)."
  exit 1
fi

# 2. Vérification d'Ubuntu 24.04+
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

# 3. Vérification que Docker est installé
if ! command -v docker >/dev/null 2>&1; then
  echo "❌ Docker n'est pas installé. Lance d'abord ton script d'installation de Docker."
  exit 1
fi

# 4. Variables de configuration
JENKINS_HOME_DIR="/opt/jenkins_home"
JENKINS_CONTAINER="jenkins"
JENKINS_IMAGE="jenkins/jenkins:lts-jdk21"
JENKINS_PORT="8080"
JENKINS_AGENT_PORT="50000"
DOCKER_GID=$(getent group docker | cut -d: -f3)

echo ".........----------------#################._.-.-DOCKER-.-._.#################----------------........."

# 5. Création du répertoire pour le bind mount
echo "📁 Création du répertoire de données Jenkins : ${JENKINS_HOME_DIR}"
mkdir -p "${JENKINS_HOME_DIR}"

# Récupération de l'UID/GID de l'utilisateur jenkins (dans l'image officielle, c'est 1000:1000)
# On s'assure que les droits sur le répertoire hôte correspondent à l'utilisateur du conteneur
JENKINS_UID=1000
JENKINS_GID=1000
chown -R ${JENKINS_UID}:${JENKINS_GID} "${JENKINS_HOME_DIR}"

echo ".........----------------#################._.-.-JENKINS-.-._.#################----------------........."

# 6. Suppression d'un éventuel conteneur existant (pour idempotence)
if docker ps -a --format '{{.Names}}' | grep -q "^${JENKINS_CONTAINER}$"; then
  echo "⚠️  Un conteneur '${JENKINS_CONTAINER}' existe déjà. Suppression..."
  docker rm -f "${JENKINS_CONTAINER}"
fi

# 7. Lancement du conteneur Jenkins
echo "🚀 Lancement du conteneur Jenkins..."
docker run -d \
  --name "${JENKINS_CONTAINER}" \
  --restart always \
  -p "${JENKINS_PORT}:8080" \
  -p "${JENKINS_AGENT_PORT}:50000" \
  -v "${JENKINS_HOME_DIR}":/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --group-add "${DOCKER_GID}" \
  "${JENKINS_IMAGE}"

echo ".........----------------#################._.-.-PLUGINS-.-._.#################----------------........."

# 8. Installation des plugins via jenkins-plugin-cli (dans le conteneur)
# On attend que le conteneur soit prêt
echo "⏳ Attente du démarrage du conteneur..."
sleep 15

# Liste des plugins
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

# Lecture du fichier plugins.txt s'il existe (situé à côté du script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_FILE="${SCRIPT_DIR}/../jenkins-plugins/plugins.txt"

if [[ -f "${PLUGIN_FILE}" ]]; then
  echo "📄 Lecture du fichier de plugins personnalisé : ${PLUGIN_FILE}"
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
    name="${line%%@*}"
    name="${name%%[[:space:]]*}"
    [[ -n "${name}" ]] && PLUGINS+=("${name}")
  done < "${PLUGIN_FILE}"
fi

# Déduplication
mapfile -t PLUGINS < <(printf '%s\n' "${PLUGINS[@]}" | awk 'NF && !seen[$0]++')

echo "📦 Installation de ${#PLUGINS[@]} plugins..."
docker exec -u root "${JENKINS_CONTAINER}" jenkins-plugin-cli --plugins "${PLUGINS[@]}"

# 9. Redémarrage de Jenkins pour prendre en compte les plugins
echo "🔄 Redémarrage de Jenkins pour activer les plugins..."
docker restart "${JENKINS_CONTAINER}"

echo ".........----------------#################._.-.-COMPLETED-.-._.#################----------------........."
echo ""
echo "✅ Jenkins est installé et démarré !"
echo "   URL : http://$(hostname -I | awk '{print $1}'):${JENKINS_PORT}"
echo "   Données : ${JENKINS_HOME_DIR} (bind mount)"
echo ""

# 10. Affichage du mot de passe initial
PASS_FILE="${JENKINS_HOME_DIR}/secrets/initialAdminPassword"
if [[ -f "${PASS_FILE}" ]]; then
  echo "🔑 Mot de passe initial admin :"
  cat "${PASS_FILE}"
else
  echo "⚠️  Fichier initialAdminPassword absent (le setup wizard est peut-être déjà passé)."
fi

echo ""
echo "ℹ️  Pour vérifier l'état du conteneur : docker ps | grep ${JENKINS_CONTAINER}"
echo "ℹ️  Pour voir les logs : docker logs -f ${JENKINS_CONTAINER}"