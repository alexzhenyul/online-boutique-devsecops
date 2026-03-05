#!/bin/bash
# Smoke Test Script for CI/CD Pipeline
# Verifies that the deployed application is healthy and responding

set -e

URL="${1:-http://localhost:3000}"
RETRIES=30
WAIT_TIME=5

echo "runnning smoke tests against $URL"

check_health() {
    local status_code=$(curl -s -o /dev/null -w "%{http_code}" "$URL/health")
    if [ "$status_code" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

echo "Waiting for service to be healthy..."

for i in $(seq 1 $RETRIES); do
    if check_health; then
        echo "Health check passed!"
        
        # Check metrics endpoint
        metrics_status=$(curl -s -o /dev/null -w "%{http_code}" "$URL/metrics")
        if [ "$metrics_status" -eq 200 ]; then
             echo "Metrics endpoint available"
        else
             echo "Metrics endpoint not responding 200 (got $metrics_status)"
        fi
        
        exit 0
    fi
    
    echo "Attempt $i/$RETRIES: Service not healthy yet. Waiting ${WAIT_TIME}s..."
    sleep $WAIT_TIME
done

echo "Smoke tests failed after $((RETRIES * WAIT_TIME)) seconds."
exit 1