#!/bin/bash
set -euo pipefail

BASE_IMAGE=$1

echo "=== Trivy config (Dockerfile) ==="
# Ici on exécute Trivy pour scanner le Dockerfile et vérifier les vulnérabilités de configuration. 
# Le script utilise l'image Docker officielle de Trivy pour effectuer l'analyse. 
# Il monte le répertoire courant dans le conteneur et spécifie que seules les vulnérabilités de gravité HIGH et CRITICAL doivent être prises en compte. 
# Si des vulnérabilités sont trouvées, le script renvoie un code de sortie 1, ce qui indique un échec du scan.
docker run --rm -v "$PWD:/app" aquasec/trivy:latest config --severity HIGH,CRITICAL --exit-code 1 /app/Dockerfile

echo "=== Trivy image (base $BASE_IMAGE) ==="
# Ici on exécute Trivy pour scanner l'image Docker spécifiée par la variable BASE_IMAGE.
# Le script utilise l'image Docker officielle de Trivy pour effectuer l'analyse.
# Il monte le socket Docker pour permettre à Trivy d'accéder aux images locales et spécifie que seules les vulnérabilités de gravité HIGH et CRITICAL doivent être prises en compte.
# Si des vulnérabilités sont trouvées, le script renvoie un code de sortie 1, ce qui indique un échec du scan.
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image --severity HIGH,CRITICAL --exit-code 1 "$BASE_IMAGE"

    # Trivy scan result processing
    exit_code=$?
    echo "Exit Code : $exit_code"

    # Check scan results
    if [[ "${exit_code}" == 1 ]]; then
        echo "Image scanning failed. Vulnerabilities found"
        exit 1;
    else
        echo "Image scanning passed. No CRITICAL vulnerabilities found"
    fi;