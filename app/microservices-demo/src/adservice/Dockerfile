# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# =========================
# Stage 1 — Build Application
# =========================
FROM --platform=$BUILDPLATFORM eclipse-temurin:24.0.2_12-jdk-noble AS builder

WORKDIR /app

# Copy Gradle wrapper & config first (better Docker cache)
COPY build.gradle gradlew ./
COPY gradle gradle

# Make gradlew executable
RUN chmod +x gradlew

# Download dependencies (cache layer)
RUN ./gradlew downloadRepos

# Copy application source
COPY . .

# Build application distribution
RUN ./gradlew installDist


# =========================
# Stage 2 — Runtime Image
# =========================
FROM eclipse-temurin:25-jre-alpine

# ✅ SECURITY FIX — patch Alpine vulnerabilities (Trivy fix)
RUN apk update && \
    apk upgrade --no-cache && \
    rm -rf /var/cache/apk/*

WORKDIR /app

# Copy built app from builder stage
COPY --from=builder /app .

# Expose application port
EXPOSE 9555

# Run service
ENTRYPOINT ["/app/build/install/hipstershop/bin/AdService"]