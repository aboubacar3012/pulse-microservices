#!/bin/bash
#trivy-k8s-scan

echo "Scanning k8s manifests"

docker run --rm -v "$PWD:/app" aquasec/trivy:latest -q config --exit-code 0 --severity LOW,MEDIUM,HIGH /app/k8s
docker run --rm -v "$PWD:/app" aquasec/trivy:latest -q config --exit-code 1 --severity CRITICAL /app/k8s

    # Trivy scan result processing
    exit_code=$?
    echo "Exit Code : $exit_code"

    # Check scan results
    if [[ ${exit_code} == 1 ]]; then
        echo "K8s scanning failed. Vulnerabilities found"
        exit 1;
    else
        echo "K8s scanning passed. No CRITICAL vulnerabilities found"
    fi;
