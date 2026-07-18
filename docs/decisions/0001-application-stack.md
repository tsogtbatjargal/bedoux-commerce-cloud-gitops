# ADR 0001: Keep the application stack small

- Status: Accepted
- Date: 2026-07-17

## Context

The project's primary objective is to learn and demonstrate AWS, EKS,
Kubernetes, delivery, and operational skills within a USD 20 monthly budget.
A large application would delay those objectives and require larger containers
and worker nodes.

## Decision

Use:

- React, Vite, and TypeScript for the frontend;
- FastAPI and Python for the API;
- PostgreSQL for relational data;
- a small adapter boundary for local filesystem/MinIO versus Amazon S3.

The API exposes OpenAPI documentation automatically, while the frontend remains
a conventional static build served from a small Nginx container.

## Consequences

- The system demonstrates both TypeScript and Python without requiring a large
  application framework.
- Containers and local development remain small.
- Shared frontend/backend types require an explicit OpenAPI generation step
  rather than a single-language monorepo type package.
- Authentication and payment processing remain outside the first release.

