#!/usr/bin/env bash
set -euo pipefail

# Vérifie que kubectl est disponible avant de continuer. updated
if ! command -v kubectl >/dev/null 2>&1; then
    printf 'Error: kubectl is not installed or is not in PATH.\n' >&2
    exit 127
fi

# Vérifie la présence des manifests et du Deployment surveillé après le déploiement.
if [[ ! -d k8s ]]; then
    printf 'Error: expected a k8s/ directory in the current working directory.\n' >&2
    exit 1
fi

if [[ ! -f k8s/deployment.yaml ]]; then
    printf 'Error: expected k8s/deployment.yaml in the current working directory.\n' >&2
    exit 1
fi

# Vérifie localement la syntaxe des manifests et leur schéma.
kubectl apply --recursive --dry-run=client --validate=strict --filename k8s/

# Demande au serveur Kubernetes de valider les manifests sans les appliquer.
kubectl apply --recursive --dry-run=server --validate=strict --filename k8s/

# Applique tous les manifests de k8s/, y compris ceux des sous-dossiers.
kubectl apply --recursive --validate=strict --filename k8s/

# Redémarre le Deployment pour récupérer la nouvelle image :latest publiée.
kubectl rollout restart --filename k8s/deployment.yaml
