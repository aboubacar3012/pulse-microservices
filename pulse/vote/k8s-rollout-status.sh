#!/usr/bin/env bash
set -euo pipefail

# Vérifie que kubectl est disponible avant de continuer.
if ! command -v kubectl >/dev/null 2>&1; then
    printf 'Error: kubectl is not installed or is not in PATH.\n' >&2
    exit 127
fi

# Vérifie la présence du manifeste du Deployment à surveiller.
if [[ ! -f k8s/deployment.yaml ]]; then
    printf 'Error: expected k8s/deployment.yaml in the current working directory.\n' >&2
    exit 1
fi

# Vérifie que le Deployment existe dans le cluster et l'espace de noms ciblés.
kubectl get --filename k8s/deployment.yaml --output=name >/dev/null

# Attend la fin du déploiement, avec un délai maximal de 180 secondes.
kubectl rollout status --filename k8s/deployment.yaml --timeout=180s

# Vérifie que Kubernetes déclare le Deployment disponible après le rollout.
kubectl wait --for=condition=Available --filename k8s/deployment.yaml --timeout=180s
