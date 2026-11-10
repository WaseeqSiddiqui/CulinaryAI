from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from fastapi import HTTPException
import pytest

from app.models.vision_schemas import GeminiFridgeScan
from app.services.gemini_service import GeminiVisionService


def service():
    result = GeminiVisionService(api_key="test-key", model_name="first-model")
    result._client = SimpleNamespace(models=SimpleNamespace(generate_content=MagicMock()))
    return result


def test_quota_failure_does_not_retry_every_model():
    vision = service()
    vision._client.models.generate_content.side_effect = RuntimeError("429 RESOURCE_EXHAUSTED quota")
    with pytest.raises(HTTPException) as error:
        vision._invoke_gemini_fridge(b"test image", "image/jpeg")
    assert error.value.status_code == 429
    assert vision._client.models.generate_content.call_count == 1


def test_fallback_uses_only_the_remaining_end_to_end_budget():
    vision = service()
    vision._client.models.generate_content.side_effect = [RuntimeError("503 unavailable"), SimpleNamespace(parsed=GeminiFridgeScan(items=[]))]
    with patch("app.services.gemini_service.time.monotonic", side_effect=[0, 0, 26]):
        vision._invoke_gemini_fridge(b"test image", "image/jpeg")
    configs = [call.kwargs["config"] for call in vision._client.models.generate_content.call_args_list]
    assert [config.http_options.timeout for config in configs] == [25000, 6000]
    assert all(config.http_options.retry_options.attempts == 1 for config in configs)


def test_expired_scan_budget_does_not_start_another_model():
    vision = service()
    vision._client.models.generate_content.side_effect = RuntimeError("timeout")
    with patch("app.services.gemini_service.time.monotonic", side_effect=[0, 0, 40]):
        with pytest.raises(HTTPException) as error:
            vision._invoke_gemini_fridge(b"test image", "image/jpeg")
    assert error.value.status_code == 504
    assert vision._client.models.generate_content.call_count == 1


def test_empty_scan_response_is_an_explicit_image_error():
    vision = service()
    vision._client.models.generate_content.return_value = SimpleNamespace(parsed=None, text=None)
    with pytest.raises(HTTPException) as error:
        vision._invoke_gemini_receipt(b"test image", "image/jpeg")
    assert error.value.status_code == 422
    assert vision._client.models.generate_content.call_count == 1
