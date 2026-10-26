#!/usr/bin/env bash
# Usage : imageName=monimage:tag bash trivy-k8s-scan.sh

set -euo pipefail

: "${imageName:?La variable imageName est requise}"
: "${WORKSPACE:=$PWD}"

TRIVY="docker run --rm -v $WORKSPACE:/root/.cache/ aquasec/trivy:0.17.2 -q image --light"

echo "Image : $imageName"

# 1. Rapport informatif (ne fait jamais échouer)
$TRIVY --exit-code 0 --severity LOW,MEDIUM,HIGH "$imageName"

# 2. Contrôle bloquant : échec si vulnérabilité CRITICAL
if $TRIVY --exit-code 1 --severity CRITICAL "$imageName"; then
  echo "Image scanning passed. Aucune vulnérabilité CRITICAL"
else
  echo "Image scanning failed. Vulnérabilités CRITICAL trouvées"
  exit 1
fi