from fastapi.testclient import TestClient
from server.app import app
import server.app as api_module
import pytest


@pytest.fixture
def client():
    with TestClient(app) as client:
        yield client


def test_health_no_secret(client, monkeypatch):
    monkeypatch.setenv("GEMINI_API_KEY", "secret-example")
    response = client.get('/api/health')
    assert response.status_code == 200
    assert response.json()['ai'] is True
    assert 'secret-example' not in response.text


def test_compute_real_worker(client):
    response = client.post('/api/compute', json={"operation": "derivative", "expression": ["Power", "x", 3]})
    assert response.status_code == 200
    assert response.json()['plain'] == '3*x**2'


def test_unsupported_expression_returns_actionable_error(client):
    response = client.post('/api/compute', json={"operation": "rref", "expression": "x"})
    assert response.status_code == 422
    assert 'matrix' in response.json()['detail']


def test_foreign_origin_rejected(client):
    response = client.post('/api/compute', json={"operation": "simplify", "expression": "x"}, headers={"Origin": "https://evil.example"})
    assert response.status_code == 403


def test_same_site_allowed(client):
    response = client.post('/api/compute', json={"operation": "simplify", "expression": "x"}, headers={"Origin": "http://127.0.0.1:5174"})
    assert response.status_code == 200


def test_oversized_request_rejected(client):
    response = client.post('/api/compute', content='x' * 4_000_001)
    assert response.status_code == 413


def test_missing_ai_key(client, monkeypatch):
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    response = client.post('/api/assist', json={"context": "x^2", "question": "Check this"})
    assert response.status_code == 503
    assert "GEMINI_API_KEY" in response.json()['detail']


def test_invalid_recognition_image(client):
    response = client.post('/api/recognize', json={"image": "data:image/png;base64,NOTREAL"})
    assert response.status_code == 422


def test_recognition_validates_response(client, monkeypatch):
    async def fake(*args, **kwargs):
        return {"latex": "", "note": "Cannot read"}
    monkeypatch.setattr(api_module, "gemini", fake)
    response = client.post('/api/recognize', json={"image": "data:image/png;base64,iVBORw0KGgo="})
    assert response.status_code == 422


def test_recognition_returns_reviewable_latex(client, monkeypatch):
    async def fake(*args, **kwargs):
        return {"latex": "x^2", "note": "Review the exponent"}
    monkeypatch.setattr(api_module, "gemini", fake)
    response = client.post('/api/recognize', json={"image": "data:image/png;base64,iVBORw0KGgo="})
    assert response.status_code == 200
    assert response.json()['latex'] == 'x^2'
