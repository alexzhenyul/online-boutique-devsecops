# Application — Google Online Boutique

This document covers the Online Boutique microservices application used as the workload for this DevSecOps project.

---

## Table of Contents

- [Application — Google Online Boutique](#application--google-online-boutique)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [Microservices](#microservices)
  - [Architecture Diagram](#architecture-diagram)
  - [Technology Stack](#technology-stack)
  - [Local Development](#local-development)
    - [Run a single service locally](#run-a-single-service-locally)
    - [Run the full stack with Docker Compose](#run-the-full-stack-with-docker-compose)
  - [Running on Kubernetes](#running-on-kubernetes)
    - [Manual apply (for testing)](#manual-apply-for-testing)
    - [Check deployment status](#check-deployment-status)
  - [Service Ports \& APIs](#service-ports--apis)
  - [Load Generation](#load-generation)

---

## Overview

The application is **Google's Online Boutique** — a cloud-native, 11-microservice e-commerce demo that simulates a real-world production workload. It was chosen because:

- It is **polyglot** — services are written in Go, Python, Java, C#, and Node.js, exercising the CI pipeline's language detection and language-aware security scanning
- It is **realistic** — service-to-service gRPC communication, real dependency trees, real CVE exposure
- It is **well-structured** — each service has its own Dockerfile and clear boundaries, making it ideal for per-service CI/CD

> Original project: [github.com/GoogleCloudPlatform/microservices-demo](https://github.com/GoogleCloudPlatform/microservices-demo)

---

## Microservices

| Service | Language | Responsibility |
|---|---|---|
| `frontend` | Go | Serves the web UI; calls all backend services via gRPC |
| `cartservice` | C# | Manages shopping cart state in Redis |
| `productcatalogservice` | Go | Returns product listings from a static JSON catalog |
| `currencyservice` | Node.js | Converts currency amounts using ECB exchange rates |
| `paymentservice` | Node.js | Processes payments (demo — no real transactions) |
| `shippingservice` | Go | Returns shipping cost estimates |
| `emailservice` | Python | Sends order confirmation emails (mocked) |
| `checkoutservice` | Go | Orchestrates the full checkout flow |
| `recommendationservice` | Python | Returns product recommendations based on cart contents |
| `adservice` | Java | Returns contextual banner ads |
| `loadgenerator` | Python / Locust | Simulates user traffic for testing and monitoring |

---

## Architecture Diagram

```
                        ┌─────────────────┐
           Browser ───► │    frontend     │ :8080
                        └───────┬─────────┘
                                │ gRPC calls
          ┌─────────────────────┼────────────────────────┐
          │                     │                        │
    ┌─────▼──────┐   ┌──────────▼───────┐   ┌────────────▼────┐
    │ cartservice│   │checkoutservice   │   │  adservice      │
    │  (C#)      │   │  (Go)            │   │  (Java)         │
    └─────┬──────┘   └──┬───────────────┘   └─────────────────┘
          │             │
        Redis    ┌──────┼───────────────────────────────────┐
                 │      │                                   │
       ┌─────────▼──┐ ┌─▼───────────────┐  ┌────────────────▼─┐
       │ payment    │ │ productcatalog  │  │  shipping        │
       │ service    │ │ service (Go)    │  │  service (Go)    │
       │ (Node.js)  │ └─────────────────┘  └──────────────────┘
       └────────────┘
                         ┌─────────────────┐  ┌──────────────────┐
                         │ recommendation  │  │  email           │
                         │ service (Python)│  │  service (Python)│
                         └─────────────────┘  └──────────────────┘

       ┌─────────────────────────────────────────┐
       │          loadgenerator (Python)         │
       │  Simulates users → sends traffic to     │
       │  frontend continuously                  │
       └─────────────────────────────────────────┘
```

All inter-service communication uses **gRPC** over port 50051 (default). Only `frontend` exposes an HTTP endpoint.

---

## Technology Stack

| Service | Language | Key Dependencies |
|---|---|---|
| `frontend` | Go 1.21 | net/http, grpc, opentelemetry |
| `cartservice` | .NET 8 / C# | StackExchange.Redis, Grpc.AspNetCore |
| `productcatalogservice` | Go 1.21 | grpc, protobuf |
| `currencyservice` | Node.js 20 | grpc-js, @grpc/proto-loader |
| `paymentservice` | Node.js 20 | grpc-js |
| `shippingservice` | Go 1.21 | grpc, protobuf |
| `emailservice` | Python 3.11 | grpcio, Jinja2 |
| `checkoutservice` | Go 1.21 | grpc, opentelemetry |
| `recommendationservice` | Python 3.11 | grpcio |
| `adservice` | Java 21 | grpc-netty, opentelemetry-javaagent |
| `loadgenerator` | Python 3.11 | locust, grpcio |

---

## Local Development

### Run a single service locally

```bash
cd app/microservices-demo/src/frontend

# Go services
go mod download
go run main.go

# Python services
pip install -r requirements.txt
python server.py

# Node.js services
npm install
node server.js

# C# services
dotnet restore
dotnet run
```

### Run the full stack with Docker Compose

```bash
cd app/microservices-demo
docker-compose up
```

Open `http://localhost:8080` to access the frontend.

---

## Running on Kubernetes

Deployed via ArgoCD using Kustomize overlays — see [`gitops/README.md`](../../gitops/README.md).

### Manual apply (for testing)

```bash
# Apply base manifests
kubectl apply -k app/microservices-demo/kubernetes-manifests/

# Or via Kustomize overlay
kubectl apply -k gitops/k8s/overlays/dev/
```

### Check deployment status

```bash
kubectl get pods -n online-boutique-dev
kubectl get services -n online-boutique-dev

# Port-forward the frontend
kubectl port-forward svc/frontend 8080:80 -n online-boutique-dev
```

---

## Service Ports & APIs

| Service | Port | Protocol |
|---|---|---|
| `frontend` | 8080 | HTTP |
| `cartservice` | 7070 | gRPC |
| `productcatalogservice` | 3550 | gRPC |
| `currencyservice` | 7000 | gRPC |
| `paymentservice` | 50051 | gRPC |
| `shippingservice` | 50051 | gRPC |
| `emailservice` | 5000 | gRPC |
| `checkoutservice` | 5050 | gRPC |
| `recommendationservice` | 8080 | gRPC |
| `adservice` | 9555 | gRPC |

---

## Load Generation

The `loadgenerator` service uses **Locust** to simulate realistic user behaviour:

- Browses the product catalog
- Adds items to cart
- Completes checkouts
- Generates continuous traffic to keep Prometheus metrics populated and dashboards active

```bash
# Scale load generator up/down
kubectl scale deployment loadgenerator --replicas=2 -n online-boutique-dev

# View load generator logs
kubectl logs -l app=loadgenerator -n online-boutique-dev --tail=50
```

The load generator is the source of traffic visible in Grafana dashboards. Scaling it up will increase RPS metrics across all services.