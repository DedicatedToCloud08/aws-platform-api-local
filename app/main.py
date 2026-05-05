from fastapi import FastAPI
from datetime import datetime
from prometheus_fastapi_instrumentator import Instrumentator
import os
import boto3
import json
import psycopg2
import redis



app = FastAPI(title="AWS Platform API")

Instrumentator().instrument(app).expose(app)

startup_time = datetime.utcnow()

# Module-level Redis client. Connection is lazy — actual TCP connection
# happens on first command, not at import time.
redis_client = redis.from_url(
    os.getenv("REDIS_URL", "redis://localhost:6379/0"),
    decode_responses=True,
    socket_connect_timeout=2,
    socket_timeout=2,
)

CACHE_KEY_DB_STATUS = "health:db_status"
CACHE_TTL_SECONDS = 30


def getdbconnection():
    """
    Connect to Postgres. Two paths:
      - Local/Compose: full connection string in DATABASE_URL
      - AWS ECS:       credentials fetched from Secrets Manager via DB_SECRET_ARN
    """
    database_url = os.getenv("DATABASE_URL")
    if database_url:
        return psycopg2.connect(database_url, connect_timeout=3)

    secret_arn = os.getenv("DB_SECRET_ARN")
    region     = os.getenv("AWS_REGION", "eu-west-1")

    client = boto3.client("secretsmanager", region_name=region)
    secret = json.loads(
        client.get_secret_value(SecretId=secret_arn)["SecretString"]
    )

    return psycopg2.connect(
        host            = secret["host"],
        port            = int(secret["port"]),
        dbname          = secret["dbname"],
        user            = secret["username"],
        password        = secret["password"],
        connect_timeout = 3
    )


def check_database_status():
    """Run an actual DB ping. Returns 'healthy' or an error string."""
    try:
        conn = getdbconnection()
        conn.close()
        return "healthy"
    except Exception as e:
        return f"unhealthy: {str(e)}"


def get_cached_db_status():
    """
    Get DB status with read-through caching.
    Cache miss = ping DB, store result with TTL.
    Cache hit = return cached value, no DB ping.
    Redis failure = fall back to direct DB ping.
    """
    try:
        cached = redis_client.get(CACHE_KEY_DB_STATUS)
        if cached is not None:
            return cached, "hit"

        fresh_status = check_database_status()
        redis_client.set(CACHE_KEY_DB_STATUS, fresh_status, ex=CACHE_TTL_SECONDS)
        return fresh_status, "miss"

    except redis.RedisError:
        # Cache layer failure — fall back to direct DB check.
        # Cache failures must not break the application.
        return check_database_status(), "bypass"


@app.get("/health")
def health_check():
    """
    Health check with Redis-cached DB status.
    DB connectivity is cached for CACHE_TTL_SECONDS to reduce load.
    """
    db_status, cache_state = get_cached_db_status()

    return {
        "status": "healthy" if db_status == "healthy" else "degraded",
        "environment": os.getenv("ENVIRONMENT", "unknownenv"),
        "timestamp": datetime.utcnow().isoformat(),
        "uptime": (datetime.utcnow() - startup_time).seconds,
        "database": db_status,
        "cache": cache_state,
    }


@app.get("/info")
def getinfo():
    """
    Purpose: To provide some information about the project
    """
    return {
        "app": "aws-platform-api",
        "environment": os.getenv("ENVIRONMENT", "Unknown env"),
        "region": os.getenv("AWS_REGION", "unknown region"),
        "version": "1.0.0"
    }


@app.get("/")
def root():
    """
    Purpose: A simple endpoint to check if the API is running or not
    """
    return {
        "message": "The API endpoint is up and running :) have fun!"
    }