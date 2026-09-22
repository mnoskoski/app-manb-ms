from unittest.mock import patch

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_crm_status_ok() -> None:
    with patch("app.api.routes.crm.get_crm_api_key", return_value="fake-key"):
        response = client.get("/integrations/crm/status")
    assert response.status_code == 200
    assert response.json() == {"crm_api_key_loaded": True}


def test_crm_status_unavailable() -> None:
    with patch("app.api.routes.crm.get_crm_api_key", side_effect=RuntimeError("boom")):
        response = client.get("/integrations/crm/status")
    assert response.status_code == 503
