"""
Smoke tests for the AWS Platform API.

These tests verify the application boots, routes are wired correctly, and
key integrations (caching, metrics) are present. They do NOT test the actual
Postgres or Redis connections — those would require integration tests with
the real services running.
"""

def test_root_endpoint(client):
    """GET / returns 200 with the welcome message."""
    response = client.get("/")
    assert response.status_code == 200
    assert "running" in response.json()["message"]

def test_info_endpoint(client):
    """GET /info returns 200 with required fields."""
    response = client.get("/info")
    assert response.status_code == 200

    body = response.json()
    assert body["app"] == "aws-platform-api"
    assert "environment" in body
    assert "region" in body
    assert "version" in body

def test_health_endpoint_responds(client):
    """GET /health returns 200 and a status field, even if DB is unreachable."""
    response = client.get("/health")
    assert response.status_code == 200

    body = response.json()
    assert "status" in body
    # Status will be 'healthy' or 'degraded' depending on whether DB is reachable
    # in the test environment. We just assert the field exists and is one of
    # the valid values.
    assert body["status"] in ("healthy", "degraded")


def test_health_includes_cache_field(client):
    """Health response includes the cache state field, proving Redis cache is wired in."""
    response = client.get("/health")
    body = response.json()
    assert "cache" in body
    # cache state is one of: hit, miss, bypass
    assert body["cache"] in ("hit", "miss", "bypass")

def test_metrics_endpoint_exists(client):
    """The /metrics endpoint exists and returns Prometheus format."""
    response = client.get("/metrics")
    assert response.status_code == 200
    # Prometheus format always has lines starting with # HELP and # TYPE
    assert "# HELP" in response.text
    assert "# TYPE" in response.text