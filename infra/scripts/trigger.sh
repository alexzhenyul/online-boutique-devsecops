#!/bin/bash

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
    echo " Unknown microservice: '${SERVICE}'"
    echo "Run ./trigger.sh without arguments to see available services"
    exit 1
fi

# Verify directory exists
if [ ! -d "app/microservices-demo/src/${SERVICE}" ]; then
    echo " Directory not found: app/microservices-demo/src/${SERVICE}"
    exit 1
fi

echo "======================================"
echo "  Triggering build for: ${SERVICE}"
echo "======================================"

git pull --rebase origin main

touch app/microservices-demo/src/${SERVICE}/.trigger-build

git add app/microservices-demo/src/${SERVICE}/.trigger-build
git commit -m "fix: trigger CI build for ${SERVICE}"
git push origin main

echo " Successfully triggered: ${SERVICE}"
echo " Monitor at: https://github.com/alexzhenyul/online-boutique-devsecops/actions"