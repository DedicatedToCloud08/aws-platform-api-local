# =============================================================================
# AWS Platform API — Local Development Makefile
# =============================================================================

# Use BASH as shell not the default SH
SHELL := /bin/bash

# Compose flags
COMPOSE_FLAGS := --profile dev --profile monitoring
COMPOSE_PROD_FLAGS := --profile prod --profile monitoring

# Default Targt
.DEFAULT_GOAL := help

# All targets are "phony"
.PHONY: help up up-prod up-debug down clean restart-dev restart-prod restart-all-dev restart-all-prod logs-dev logs-prod logs-dev-api logs-prod-api shell psql lint test ci

# =============================================================================
# TARGETS — Help
# =============================================================================

help:  ## Show this help message
	@echo "Usage: make <target>"
	@echo ""
	@echo "Lifecycle:"
	@echo "  up          		Start dev stack (api-dev + postgres + redis + monitoring)"
	@echo "  up-prod     		Start prod stack (api-prod + postgres + redis + monitoring)"
	@echo "  up-debug    		Start debug stack (pgadmin)"
	@echo "  down        		Stop all services (preserves volumes)"
	@echo "  clean       		Stop all services AND destroy volumes (data loss!)"
	@echo "  restart-dev     	Restart just the dev api container"
	@echo "  restart-prod     	Restart just the prod api container"
	@echo "  restart-all-dev    	Restart the entire dev stack (api-dev + postgres + redis + monitoring)"
	@echo "  restart-all-prod   	Restart the entire prod stack (api-prod + postgres + redis + monitoring)"
	@echo ""
	@echo "Daily ops:"
	@echo "  logs        Tail logs from all running services"
	@echo "  logs-api    Tail logs from just the api container"
	@echo "  shell       Open a bash shell in the api container"
	@echo "  psql        Open a psql prompt in the postgres container"
	@echo ""
	@echo "Quality:"
	@echo "  lint        Run ruff against the app code"
	@echo "  test        Run pytest in the api container"
	@echo "  ci          Full local CI: lint + test + build prod + security scan"


# =============================================================================
# TARGETS — Lifecycle
# =============================================================================


## Start dev stack with monitoring
up:
	docker compose $(COMPOSE_FLAGS) up --build -d
	@echo ""
	@echo "Stack is up. Endpoints:"
	@echo "  DEV-API:        http://localhost:8000"
	@echo "  Prometheus: http://localhost:9090"
	@echo "  Grafana:    http://localhost:3000  (admin/admin)"

## Start prod stack with monitoring
up-prod:
	docker compose $(COMPOSE_PROD_FLAGS) up --build -d
	@echo ""
	@echo "Stack is up. Endpoints:"
	@echo "  PROD-API:   http://localhost:8070"
	@echo "  Prometheus: http://localhost:9090"
	@echo "  Grafana:    http://localhost:3000  (admin/admin)"

## Start pgadmin to debug tables and DB
up-debug:
	docker compose --profile debug up -d
	@echo ""
	@echo "Stack is up. Endpoints:"
	@echo "  pgadmin:   http://localhost:5050 (TBA in .env)/admin)"	

## To remove all docker compose containers but preserve named volumes
down:
	docker compose --profile "*" down
	@echo "All containers destroyed but volumes are preserved."
	@echo "Please use 'make clean' for cleanup and destroy volumes."

## To remove all docker compose containers and named volumes
clean:
	docker compose --profile "*" down -v
	@echo "All containers and volumes destroyed."

## To restart the API DEV container
restart-dev:  
	docker compose $(COMPOSE_FLAGS) restart api-dev

## To restart the API PROD container
restart-prod:  
	docker compose $(COMPOSE_FLAGS) restart api-prod

## To restart the entire stack for DEV
restart-all-dev:  
	docker compose $(COMPOSE_FLAGS) restart

## To restart the entire stack for PROD
restart-all-prod:  
	docker compose $(COMPOSE_PROD_FLAGS) restart


# =============================================================================
# TARGETS — Daily Ops
# =============================================================================
## Tail logs from all services dev stack
logs-dev:
	docker compose $(COMPOSE_FLAGS) logs -f --tail 100

## Tail logs from all services prod stack
logs-prod:
	docker compose $(COMPOSE_PROD_FLAGS) logs -f --tail 100

## Tail logs from api-dev service
logs-dev-api:
	docker compose $(COMPOSE_FLAGS) logs -f --tail 100 api-dev

## Tail logs from api-dev service
logs-prod-api:
	docker compose $(COMPOSE_PROD_FLAGS) logs -f --tail 100 api-prod

## To open a shell in our api-dev container
shell-dev:
	docker compose $(COMPOSE_FLAGS) exec api-dev bash

## To open a shell in our api-dev container
shell-prod:
	docker compose $(COMPOSE_PROD_FLAGS) exec api-dev bash

## Open a psql prompt in the postgres container
psql:  
	docker compose $(COMPOSE_FLAGS) exec postgres psql -U $${POSTGRES_USER:-appuser} -d $${POSTGRES_DB:-appdb}

# =============================================================================
# Quality
# =============================================================================

## Run ruff against app code
lint: 
	docker compose $(COMPOSE_FLAGS) exec api-dev ruff check /app

## Run pytest in api container
test:  
	docker compose $(COMPOSE_FLAGS) exec api-dev pytest /app/tests -v

## Full local CI pipeline
ci: 
	@echo "=== Step 1: Lint ==="
	$(MAKE) lint
	@echo ""
	@echo "=== Step 2: Test ==="
	$(MAKE) test
	@echo ""
	@echo "=== Step 3: Build production image ==="
	docker build -f docker/Dockerfile.prod -t aws-platform-api:ci-$(shell git rev-parse --short HEAD 2>/dev/null || echo "local") .
	@echo ""
	@echo "=== Step 4: Security scan (Trivy) ==="
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:latest image --severity HIGH,CRITICAL aws-platform-api:ci-$(shell git rev-parse --short HEAD 2>/dev/null || echo "local")
	@echo ""
	@echo "=== CI complete. Image tagged: aws-platform-api:ci-$(shell git rev-parse --short HEAD 2>/dev/null || echo "local") ==="