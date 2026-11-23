import base64
from io import BytesIO
import json

from fastapi import HTTPException
from fastapi.testclient import TestClient
from google.genai import types
import httpx
from PIL import Image
import pytest

import app.main as main
from app.models.schemas import (
    MatchProductRequest, NormalizeShoppingQueryRequest, ProductCandidateInput,
)
from app.models.vision_schemas import (
    CookingStepValidationResponse, GeminiFridgeScan, GeminiReceiptResponse,
    MealNutritionEstimate, StepExplanationResponse,
)
from app.services.ai_client import (
    DEFAULT_TEXT_MODEL, DEFAULT_VISION_MODEL, GroqModelClient, strict_schema,
)
from app.services.gemini_service import KitchenAIService
from app.services.product_matcher import ProductMatcher


@pytest.fixture(autouse=True)
def groq_environment(monkeypatch):
    monkeypatch.setenv("AI_PROVIDER", "groq")
    monkeypatch.delenv("GROQ_TEXT_MODEL", raising=False)
    monkeypatch.delenv("GROQ_VISION_MODEL", raising=False)


def image_bytes():
    buffer = BytesIO()
    Image.new("RGB", (24, 24), "goldenrod").save(buffer, format="PNG")
    return buffer.getvalue()


def groq_client(result, requests, *, finish_reason="stop"):
    def respond(request):
        requests.append(request)
        assert request.url == "https://api.groq.com/openai/v1/chat/completions"
        assert request.headers["authorization"] == "Bearer test-groq-key"
        return httpx.Response(200, json={"choices": [{
            "finish_reason": finish_reason,
            "message": {"content": result if isinstance(result, str) else json.dumps(result)},
        }]})
    return GroqModelClient("test-groq-key", httpx.Client(transport=httpx.MockTransport(respond)))


PHOTO_CHECK = CookingStepValidationResponse(
    status="needs_more_time", headline="Keep stirring", feedback="Onions are pale.",
    action_suggestion="Continue gently", image_sufficient=True, confidence=0.8,
)
NUTRITION = MealNutritionEstimate(
    dish_name="Rice", portion_description="A bowl", calories=200,
    protein_grams=4, carbohydrate_grams=44, fat_grams=1, fiber_grams=1,
    confidence=0.6,
)
EXPLANATION = StepExplanationResponse(recipe_title="Rice", step_number=1, action="Simmer rice")


@pytest.mark.parametrize("operation, payload, photo", [
    ("chat", "Try a quick rice dish.", False),
    ("step_chat", "Keep stirring gently.", False),
    ("explanation", EXPLANATION.model_dump(), False),
    ("receipt", GeminiReceiptResponse().model_dump(), True),
    ("fridge", GeminiFridgeScan().model_dump(), True),
    ("nutrition", NUTRITION.model_dump(), True),
    ("photo_check", PHOTO_CHECK.model_dump(), True),
])
def test_every_kitchen_operation_routes_to_the_correct_groq_model(operation, payload, photo):
    requests = []
    service = KitchenAIService(api_key="test-groq-key")
    service._client = groq_client(payload, requests)
    image = image_bytes()
    if operation == "chat":
        result = service.ask_chef("What can I eat?", [{"name": "Rice", "quantity": 1, "unit": "kg"}])
        assert result == payload
    elif operation == "step_chat":
        result = service.chat_cooking_step("Rice", 1, "Simmer rice", "What next?")
        assert result == payload
    elif operation == "explanation":
        assert service.get_step_explanation("Rice", 1, "Simmer rice").step_number == 1
    elif operation == "receipt":
        assert service._invoke_gemini_receipt(image, "image/png").items == []
    elif operation == "fridge":
        assert service._invoke_gemini_fridge(image, "image/png").items == []
    elif operation == "nutrition":
        assert service.analyze_meal(image, "image/png").calories == 200
    else:
        result = service.validate_cooking_step(image, "image/png", "Rice", 1, "Simmer rice")
        assert result.status == "needs_more_time"
        assert result.image_hash
    assert len(requests) == 1
    body = json.loads(requests[0].content)
    assert body["model"] == (DEFAULT_VISION_MODEL if photo else DEFAULT_TEXT_MODEL)
    assert body["reasoning_effort"] == ("none" if photo else "low")
    images = [part for part in body["messages"][0]["content"] if part["type"] == "image_url"]
    assert bool(images) == photo
    if photo:
        assert images[0]["image_url"]["url"] == "data:image/png;base64," + base64.b64encode(image).decode()
    if isinstance(payload, dict):
        assert body["response_format"]["json_schema"]["strict"] is True
    else:
        assert requests[0].extensions["timeout"]["read"] == 7.0


def test_groq_product_matching_keeps_stock_validation():
    requests = []
    matcher = ProductMatcher(api_key="test-groq-key")
    matcher._client = groq_client({"chosen_index": 0, "units_to_buy": 1, "confidence": 0.99, "reason": "Milk"}, requests)
    request = MatchProductRequest(name="milk", quantity=1, unit="L", candidates=[
        ProductCandidateInput(name="Milk", size="1 L", price=200, in_stock=False),
    ])
    with pytest.raises(HTTPException, match="out-of-stock"):
        matcher.match(request)
    body = json.loads(requests[0].content)
    assert body["model"] == DEFAULT_TEXT_MODEL
    assert body["response_format"]["json_schema"]["strict"] is True


def test_groq_text_normalization_still_checks_protected_product_forms():
    requests = []
    matcher = ProductMatcher(api_key="test-groq-key")
    matcher._client = groq_client({"search_query": "milk", "canonical_name": "milk", "confidence": 0.99, "changed": True, "reason": "Shorter query"}, requests)
    result = matcher.normalize_query(NormalizeShoppingQueryRequest(name="milk powder", quantity=1, unit="kg"))
    assert result.search_query == "milk powder"
    assert result.changed is False
    assert result.confidence == 0
    assert json.loads(requests[0].content)["model"] == DEFAULT_TEXT_MODEL


def test_missing_groq_key_does_not_use_a_gemini_key_or_fake_live_chat(monkeypatch):
    monkeypatch.delenv("GROQ_API_KEY", raising=False)
    monkeypatch.setenv("GEMINI_API_KEY", "unrelated-gemini-key")
    service = KitchenAIService()
    monkeypatch.setattr(main, "vision_service", service)
    response = TestClient(main.app).post("/chef-chat", json={"message": "Hello"})
    assert response.status_code == 503
    assert "GROQ_API_KEY" in response.json()["detail"]
    assert not service.api_key


def test_configured_key_builds_groq_clients_for_both_services(monkeypatch):
    monkeypatch.setenv("GROQ_API_KEY", "test-groq-key")
    for service in [KitchenAIService(), ProductMatcher()]:
        assert service.provider == "groq"
        client = service._get_client()
        assert isinstance(client, GroqModelClient)
        client.close()


def test_vision_configuration_rejects_a_text_only_model(monkeypatch):
    monkeypatch.setenv("GROQ_VISION_MODEL", DEFAULT_TEXT_MODEL)
    with pytest.raises(ValueError, match="text-only"):
        KitchenAIService(api_key="test-groq-key")


def test_image_is_never_sent_to_gpt_oss():
    requests = []
    client = groq_client("ignored", requests)
    with pytest.raises(ValueError, match="cannot process images"):
        client.generate_content(model=DEFAULT_TEXT_MODEL, contents=[types.Part.from_bytes(data=image_bytes(), mime_type="image/png")])
    assert requests == []


def test_strict_schema_closes_nested_objects_without_changing_validation_schema():
    original = GeminiReceiptResponse.model_json_schema()
    converted = strict_schema(original)
    assert converted["additionalProperties"] is False
    assert set(converted["required"]) == set(converted["properties"])
    item = converted["$defs"]["GeminiReceiptItem"]
    assert item["additionalProperties"] is False
    assert set(item["required"]) == set(item["properties"])
    assert "default" not in item["properties"]["confidence"]
    assert "default" in original["$defs"]["GeminiReceiptItem"]["properties"]["confidence"]


@pytest.mark.parametrize("status, expected", [(400, 400), (401, 503), (403, 503), (404, 503), (429, 429), (503, 503)])
def test_provider_errors_are_sanitized_and_not_retried(status, expected):
    calls = []
    def respond(request):
        calls.append(request)
        return httpx.Response(status, json={"error": "sensitive upstream content"})
    client = GroqModelClient("test-groq-key", httpx.Client(transport=httpx.MockTransport(respond)))
    with pytest.raises(HTTPException) as error:
        client.generate_content(model=DEFAULT_TEXT_MODEL, contents="Hello")
    assert error.value.status_code == expected
    assert "sensitive" not in error.value.detail
    assert "test-groq-key" not in error.value.detail
    assert len(calls) == 1


@pytest.mark.parametrize("payload, finish", [("not json", "stop"), ('{"items": 7}', "stop"), ('{"items": []}', "length")])
def test_invalid_or_truncated_vision_output_is_rejected(payload, finish):
    client = groq_client(payload, [], finish_reason=finish)
    with pytest.raises(HTTPException) as error:
        client.generate_content(model=DEFAULT_VISION_MODEL, contents="Read food", config=types.GenerateContentConfig(response_schema=GeminiFridgeScan))
    assert error.value.status_code == 502


def test_scan_timeout_respects_the_remaining_scan_budget():
    requests = []
    client = groq_client(GeminiFridgeScan().model_dump(), requests)
    client.generate_content(model=DEFAULT_VISION_MODEL, contents="Read food", config=types.GenerateContentConfig(response_schema=GeminiFridgeScan, http_options=types.HttpOptions(timeout=6000)))
    assert requests[0].extensions["timeout"]["read"] == 6.0


def test_timed_out_photo_does_not_invent_a_successful_cooking_check():
    requests = []
    def respond(request):
        requests.append(request)
        raise httpx.ReadTimeout("Timed out")
    service = KitchenAIService(api_key="test-groq-key")
    service._client = GroqModelClient("test-groq-key", httpx.Client(transport=httpx.MockTransport(respond)))
    result = service.validate_cooking_step(image_bytes(), "image/png", "Rice", 1, "Simmer rice")
    assert result.status == "unable_to_assess"
    assert not result.image_sufficient
    assert result.confidence == 0
    assert len(requests) == 1
