#!/usr/bin/env bash
# Usage : bash kubesec-scan.sh [dossier]   (défaut : k8s)

set -euo pipefail

DIR="${1:-k8s}"
MIN_SCORE=5
FAILED=0

for file in "$DIR"/*.yaml; do
  echo "==> $file"

  # Scan avec l'image Docker kubesec
  result=$(docker run -i --rm kubesec/kubesec:512c5e0 scan /dev/stdin < "$file")

  # Pour chaque ressource du fichier
  for i in $(seq 0 $(( $(jq length <<<"$result") - 1 ))); do
    object=$(jq -r ".[$i].object" <<<"$result")
    valid=$(jq -r ".[$i].valid" <<<"$result")
    score=$(jq -r ".[$i].score" <<<"$result")

    # Ignorer les ressources non supportées (Service, Ingress...)
    if [[ "$valid" != "true" ]]; then
      echo "    [SKIP] $object"
    elif (( score >= MIN_SCORE )); then
      echo "    [OK]   $object : score $score"
    else
      echo "    [FAIL] $object : score $score (minimum $MIN_SCORE)"
      FAILED=1
    fi
  done
done

exit $FAILED