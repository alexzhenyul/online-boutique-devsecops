#!/bin/bash

# ── Repo root (2 levels up from infra/scripts/) ───────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

SERVICE=$1

if [ -z "$SERVICE" ]; then
    echo "Usage: ./trigger.sh <microservice-name>"
    echo ""
    echo "Available microservices:"
    echo "  frontend"
    echo "  cartservice"
    echo "  checkoutservice"
    echo "  currencyservice"
    echo "  emailservice"
    echo "  paymentservice"
    echo "  productcatalogservice"
    echo "  recommendationservice"
    echo "  shippingservice"
    echo "  adservice"
    echo "  loadgenerator"
    echo "  shoppingassistantservice"
    exit 1
fi

VALID_SERVICES=(
    frontend
    cartservice
    checkoutservice
    currencyservice
    emailservice
    paymentservice
    productcatalogservice
    recommendationservice
    shippingservice
    adservice
    loadgenerator
    shoppingassistantservice
)

# Validate service name
if [[ ! " ${VALID_SERVICES[@]} " =~ " ${SERVICE} " ]]; then
    echo "Unknown microservice: '${SERVICE}'"
    echo "Run ./trigger.sh without arguments to see available services"
    exit 1
fi

SERVICE_BASE="${REPO_ROOT}/app/microservices-demo/src/${SERVICE}"

# Verify directory exists
if [ ! -d "${SERVICE_BASE}" ]; then
    echo "Directory not found: ${SERVICE_BASE}"
    exit 1
fi

# ── Handle nested Dockerfile (e.g. cartservice/src/Dockerfile) ───
if [ -f "${SERVICE_BASE}/Dockerfile" ]; then
    TRIGGER_PATH="${SERVICE_BASE}/.trigger-build"
elif [ -f "${SERVICE_BASE}/src/Dockerfile" ]; then
    TRIGGER_PATH="${SERVICE_BASE}/src/.trigger-build"
else
    echo "No Dockerfile found for ${SERVICE}"
    exit 1
fi

echo "======================================"
echo "  Repo root  : ${REPO_ROOT}"
echo "  Triggering : ${SERVICE}"
echo "  Trigger at : ${TRIGGER_PATH}"
echo "======================================"

cd "${REPO_ROOT}"

git pull --rebase origin main

# Force a change by writing current timestamp
echo "$(date)" > "${TRIGGER_PATH}"

git add "${TRIGGER_PATH}"
git commit -m "fix: trigger CI build for ${SERVICE}"
git push origin main

echo "Successfully triggered: ${SERVICE}"
echo "Monitor at: https://github.com/alexzhenyul/online-boutique-devsecops/actions"
