#!/bin/bash
# ==============================================================================
# Installation Jenkins LTS (Native) — Ubuntu 24.04+
# Prérequis : Docker, Java, Node.js, Maven, Python doivent être installés sur le serveur.
# ==============================================================================

set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Exécute ce script en root (sudo)."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo ".........----------------#################._.-.-REPO JENKINS LTS-.-._.#################----------------........."
# Installation des prérequis de base pour Jenkins
apt-get update -y
apt-get install -y curl ca-certificates gnupg fontconfig

# Ajout de la clé et du dépôt Jenkins
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key \
  -o /etc/apt/keyrings/jenkins-keyring.asc
chmod a+r /etc/apt/keyrings/jenkins-keyring.asc
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  > /etc/apt/sources.list.d/jenkins.list

apt-get update -y
apt-get install -y jenkins

echo ".........----------------#################._.-.-DOCKER-.-._.#################----------------........."
# Ajout de l'utilisateur jenkins au groupe docker
# C'est crucial pour que les pipelines puissent utiliser 'docker run'
if getent group docker >/dev/null 2>&1; then
  usermod -aG docker jenkins
  echo "Utilisateur jenkins ajouté au groupe docker."
else
  echo "⚠️ Groupe docker introuvable. Assure-toi que Docker est installé sur le serveur."
fi

echo ".........----------------#################._.-.-PLUGINS-.-._.#################----------------........."
# Liste des plugins DevSecOps
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
  configuration-as-code
)

# Installation via jenkins-plugin-cli (installé avec le paquet jenkins)
if command -v jenkins-plugin-cli >/dev/null 2>&1; then
  echo "Installation des plugins..."
  jenkins-plugin-cli --plugins "${PLUGINS[@]}" --plugin-download-directory /var/lib/jenkins/plugins
  chown -R jenkins:jenkins /var/lib/jenkins/plugins
else
  echo "⚠️ jenkins-plugin-cli absent — installe les plugins depuis l'interface web."
fi

echo ".........----------------#################._.-.-DEMARRAGE-.-._.#################----------------........."
systemctl daemon-reload
systemctl enable jenkins
# Redémarrage pour prendre en compte le groupe docker
systemctl restart jenkins

echo "Attente du démarrage de Jenkins (port 8080)..."
for _ in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:8080/login >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

echo ".........----------------#################._.-.-COMPLETED-.-._.#################----------------........."
echo "✅ Jenkins est installé !"
echo "URL : http://$(hostname -I | awk '{print $1}'):8080"

if [[ -f /var/lib/jenkins/secrets/initialAdminPassword ]]; then
  echo "🔑 Mot de passe initial admin :"
  cat /var/lib/jenkins/secrets/initialAdminPassword
else
  echo "⚠️ Fichier initialAdminPassword absent."
fi