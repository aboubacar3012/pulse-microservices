#!/bin/bash
set -euo pipefail

BASE_IMAGE=$1

echo "=== Trivy config (Dockerfile) ==="
docker run --rm -v "$PWD:/app" aquasec/trivy:latest config --severity HIGH,CRITICAL --exit-code 1 /app/Dockerfile

echo "=== Trivy image (base $BASE_IMAGE) ==="
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