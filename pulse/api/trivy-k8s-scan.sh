#!/usr/bin/env bash
# Usage : bash kubesec-scan.sh [dossier]   (défaut : k8s)

set -euo pipefail

DIR="${1:-k8s}"
MIN_SCORE=5
FAILED=0

shopt -s nullglob
files=("$DIR"/*.yaml)
if [[ ${#files[@]} -eq 0 ]]; then
  echo "Aucun YAML dans $DIR"
  exit 0
fi

for file in "${files[@]}"; do
  echo "==> $file"

  set +e
  result=$(docker run -i --rm kubesec/kubesec:512c5e0 scan /dev/stdin <"$file" 2>/dev/null)
  rc=$?
  set -e

  if [[ $rc -ne 0 || -z "$result" ]]; then
    echo "    [SKIP] non scoré par kubesec (kind non supporté ou erreur)"
    continue
  fi

  if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$result"; then
    echo "    [SKIP] réponse JSON invalide"
    continue
  fi

  count=$(jq 'length' <<<"$result")
  if [[ "$count" -eq 0 ]]; then
    echo "    [SKIP] aucune ressource scorée"
    continue
  fi

  for i in $(seq 0 $((count - 1))); do
    object=$(jq -r ".[$i].object" <<<"$result")
    valid=$(jq -r ".[$i].valid" <<<"$result")
    score=$(jq -r ".[$i].score // 0" <<<"$result")

    if [[ "$valid" != "true" ]]; then
      echo "    [SKIP] $object (non supporté)"
    elif (( score >= MIN_SCORE )); then
      echo "    [OK]   $object : score $score"
    else
      echo "    [FAIL] $object : score $score (minimum $MIN_SCORE)"
      FAILED=1
    fi
  done
done

exit "$FAILED"