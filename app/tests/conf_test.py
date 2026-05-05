import pytest
from fastapi.testclient import TestClient
from main import app

@pytest.fixture(scope="module")
def client():
    """
    Provides a TestClient that wraps the FastAPI app.
    """
    with TestClient(app) as c:
        yield c