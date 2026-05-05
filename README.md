# AWS Platform API — Local Development Environment

Production-grade local development environment for `aws-platform-api`, mirroring its 
AWS ECS Fargate deployment using Docker Compose. Demonstrates container orchestration, 
networking, observability, and CI/CD patterns that map 1:1 to AWS managed services.

## Architecture

A six-service Docker Compose stack with profile-based environment selection:

┌─────────────────────────────────────────────────────────┐
│  Frontend network                                       │
│  ┌──────────────┐                                       │
│  │  api (FastAPI) │ ← public-facing                      │
│  └──────────────┘                                       │
├─────────────────────────────────────────────────────────┤
│  Backend network                                        │
│  ┌──────────────┐  ┌──────────┐  ┌────────────────────┐ │
│  │  api         │  │ postgres │  │ redis              │ │
│  │  (cont'd)    │  │  (DB)    │  │ (cache)            │ │
│  └──────────────┘  └──────────┘  └────────────────────┘ │
│  ┌──────────────┐  ┌──────────┐  ┌────────────────────┐ │
│  │  prometheus  │  │ grafana  │  │ pgadmin (debug)    │ │
│  └──────────────┘  └──────────┘  └────────────────────┘ │
└─────────────────────────────────────────────────────────┘

| Compose service        | AWS production equivalent          |
|------------------------|------------------------------------|
| api (FastAPI)          | ECS Fargate task                   |
| postgres               | RDS PostgreSQL                     |
| redis                  | ElastiCache for Redis              |
| Frontend/backend nets  | VPC subnets + security groups      |
| Named volumes          | EBS volumes / RDS storage          |
| Prometheus + Grafana   | Amazon Managed Prometheus + Grafana|
| Healthchecks           | ECS task healthcheck               |
| Resource limits        | ECS task definition cpu/memory     |

## Quick Start

```bash
git clone <repo-url>
cd aws-platform-api-local
cp .env.example .env
make up
```

Endpoints:
- API:        http://localhost:8000
- Prometheus: http://localhost:9090
- Grafana:    http://localhost:3000 (admin/admin)

## Profiles

| Profile      | Services started                                    |
|--------------|-----------------------------------------------------|
| `dev`        | api-dev (hot-reload), postgres, redis              |
| `prod`       | api-prod (production image), postgres, redis       |
| `monitoring` | prometheus, grafana, cadvisor (added to any above) |
| `debug`      | pgadmin (added to any above)                       |

Combine profiles: `docker compose --profile dev --profile monitoring up`

## Make Targets

Run `make help` for the full list. Key targets:

- `make up` — start dev stack with monitoring
- `make up-prod` — start prod stack with monitoring
- `make logs-dev-api` — tail api logs
- `make psql` — open psql in postgres container
- `make test` — run pytest in the api container
- `make lint` — run ruff against the code
- `make ci` — full local CI pipeline (lint + test + build + scan)
- `make clean` — destroy everything including volumes

## Key Engineering Decisions

### Network isolation

Postgres and Redis are on a `backend` network only — not reachable from the host. 
The API service straddles `frontend` and `backend`, the only path between public 
traffic and the data layer. Mirrors VPC subnet + security group chaining.

### Healthcheck-gated startup

Services use `depends_on: condition: service_healthy`. The API only starts after 
Postgres responds to `pg_isready` and Redis responds to `PING`. No race conditions, 
no retry loops in application code.

### Cache-aside with fail-open

`/health` caches DB connectivity for 30s in Redis. On Redis failure, the cache 
layer is bypassed transparently and the health check still works — cache failures 
never break the application.

### Production image hardening

`Dockerfile.prod` is multi-stage (build deps in stage 1, runtime libraries only 
in stage 2), runs as non-root (`appuser`), uses pinned base images, and is 
~30% smaller than the dev image.

## Observability

The dashboard focuses on application-level metrics from `prometheus-fastapi-instrumentator`:
request rate, P95 latency, and HTTP status code distribution — the RED metrics 
(Rate, Errors, Duration).

Container resource metrics from cAdvisor were excluded due to a known upstream 
issue (cadvisor#3793) where cAdvisor on Docker Desktop / WSL2 cannot negotiate 
the required Docker API version, producing metrics without `name`/`image` labels. 
On native Linux Docker the issue does not occur. In production AWS, this layer 
would be replaced by CloudWatch Container Insights.

## Local CI Pipeline

`make ci` runs the full pipeline locally:

1. **Lint** — `ruff check`
2. **Test** — `pytest` against the test suite (5 smoke tests covering all 
   endpoints + `/metrics`)
3. **Build** — `docker build` of the production image, tagged with Git short SHA 
   (e.g. `aws-platform-api:ci-e3b6483`)
4. **Scan** — Trivy security scan, filtered to HIGH/CRITICAL severity

### Vulnerability triage

The scan distinguishes between:

- **Application dependency findings** — Vulnerability scans are point-in-time. CVE-2024-47874 was identified and remediated by upgrading FastAPI from 0.115.0 to 0.116.0. Subsequent scans detected CVE-2025-62727, disclosed after the upgrade — illustrating that supply-chain security is continuous, not one-time. In production, this is addressed via Dependabot/Renovate-style automated dependency PRs and scheduled rescan jobs.

- **OS package findings without upstream fix** — common in Debian-based images 
  where CVEs are disclosed before patches are released to the stable channel. 
  These are reported with no `Fixed Version` available and are tracked but 
  not actionable from the consumer side. Mitigation in production is base 
  image rotation as upstream patches land.

The same pattern applies in production CI: fail fast on findings with 
upstream fixes; track-and-monitor findings without them.

## Stack

- **API**: FastAPI 0.115, Python 3.12, psycopg2 (PostgreSQL), redis-py
- **Storage**: PostgreSQL 16, Redis 7
- **Observability**: Prometheus 2.54, Grafana 11, prometheus-fastapi-instrumentator 7
- **Tooling**: Docker Compose, Make, ruff, pytest, Trivy
- **Tested on**: Docker Desktop on Windows 11 (WSL2 backend), Git Bash

## Project Structure
aws-platform-api-local/
├── app/
│   ├── main.py
│   ├── requirements.txt
│   └── tests/
│       ├── conftest.py
│       └── test_main.py
├── docker/
│   ├── Dockerfile.dev
│   ├── Dockerfile.prod
│   └── init.sql
├── monitoring/
│   ├── prometheus.yml
│   └── grafana/
│       ├── datasources/prometheus.yml
│       └── dashboards/
│           ├── dashboard.yml
│           └── overview.json
├── docker-compose.yml
├── Makefile
├── .env.example
├── .gitignore
└── README.md

## License
MIT