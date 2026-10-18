import json
from types import SimpleNamespace

from fastapi import HTTPException
import pytest
from pydantic import ValidationError

from app.models.schemas import (
    MatchProductRequest,
    MatchProductResponse,
    NormalizeShoppingQueryRequest,
    NormalizeShoppingQueryResponse,
    ProductCandidateInput,
)
from app.services.product_matcher import (
    DEFAULT_GEMINI_MODEL,
    MATCH_PROMPT,
    MATCH_RESPONSE_SCHEMA,
    ProductMatcher,
    NORMALIZE_PROMPT,
    NORMALIZE_RESPONSE_SCHEMA,
)


def request() -> MatchProductRequest:
    return MatchProductRequest(
        name="milk",
        quantity=2,
        unit="L",
        candidates=[
            ProductCandidateInput(name="Milk 1L", size="1 L", price=300, in_stock=True),
            ProductCandidateInput(name="Milk 2L", size="2 L", price=550, in_stock=False),
        ],
    )


def test_valid_match_is_accepted():
    result = MatchProductResponse(
        chosen_index=0, units_to_buy=2, confidence=0.95, reason="Exact coverage"
    )
    assert ProductMatcher.validate_result(request(), result) == result


def test_no_match_with_null_quantity_is_accepted():
    result = MatchProductResponse(
        chosen_index=None,
        units_to_buy=None,
        confidence=0.8,
        reason="No in-stock candidate fits",
    )
    assert ProductMatcher.validate_result(request(), result) == result


@pytest.mark.parametrize(
    "result",
    [
        MatchProductResponse(chosen_index=3, units_to_buy=1, confidence=0.9, reason="bad"),
        MatchProductResponse(chosen_index=1, units_to_buy=1, confidence=0.9, reason="bad"),
    ],
)
def test_invalid_or_out_of_stock_choice_is_rejected(result):
    with pytest.raises(HTTPException):
        ProductMatcher.validate_result(request(), result)


@pytest.mark.parametrize(
    "payload",
    [
        {
            "chosen_index": 0,
            "units_to_buy": None,
            "confidence": 0.9,
            "reason": "missing quantity",
        },
        {
            "chosen_index": None,
            "units_to_buy": 1,
            "confidence": 0.9,
            "reason": "quantity without choice",
        },
        {
            "chosen_index": 0,
            "units_to_buy": 0,
            "confidence": 0.9,
            "reason": "zero quantity",
        },
        {
            "chosen_index": 0.0,
            "units_to_buy": 1,
            "confidence": 0.9,
            "reason": "non-integer index",
        },
        {
            "chosen_index": 0,
            "units_to_buy": 1.5,
            "confidence": 0.9,
            "reason": "non-integer quantity",
        },
    ],
)
def test_response_schema_rejects_inconsistent_or_non_integer_output(payload):
    with pytest.raises(ValidationError):
        MatchProductResponse.model_validate(payload)


class FakeModels:
    def __init__(self, parsed):
        self.parsed = parsed
        self.call = None

    def generate_content(self, **kwargs):
        self.call = kwargs
        return SimpleNamespace(parsed=self.parsed, text="")


def test_match_uses_zero_based_candidates_and_structured_deterministic_output():
    models = FakeModels(
        {
            "chosen_index": 0,
            "units_to_buy": 2,
            "confidence": 0.95,
            "reason": "Exact coverage",
        }
    )
    matcher = ProductMatcher(
        api_key="test-key",
        model_name=DEFAULT_GEMINI_MODEL,
    )
    matcher._client = SimpleNamespace(models=models)

    result = matcher.match(request())

    assert result.chosen_index == 0
    assert result.units_to_buy == 2
    assert models.call["model"] == DEFAULT_GEMINI_MODEL
    assert models.call["contents"][0] == MATCH_PROMPT
    payload = json.loads(models.call["contents"][1])
    assert [candidate["index"] for candidate in payload["candidates"]] == [0, 1]
    config = models.call["config"]
    assert config.temperature == 0.0
    assert config.response_mime_type == "application/json"
    assert config.response_schema is None
    assert config.response_json_schema == MATCH_RESPONSE_SCHEMA


def test_match_rejects_mocked_out_of_stock_gemini_choice():
    models = FakeModels(
        {
            "chosen_index": 1,
            "units_to_buy": 1,
            "confidence": 0.99,
            "reason": "Wrong stock choice",
        }
    )
    matcher = ProductMatcher(api_key="test-key")
    matcher._client = SimpleNamespace(models=models)

    with pytest.raises(HTTPException, match="out-of-stock") as error:
        matcher.match(request())

    assert error.value.status_code == 502


def test_model_name_can_be_overridden(monkeypatch):
    monkeypatch.setenv("GEMINI_MODEL", "gemini-test-model")
    assert ProductMatcher(api_key="test-key").model_name == "gemini-test-model"


def normalize_request(name: str = "Olpers milkk") -> NormalizeShoppingQueryRequest:
    return NormalizeShoppingQueryRequest(name=name, quantity=1, unit="L")


def test_normalize_query_uses_structured_deterministic_output():
    models = FakeModels(
        {
            "search_query": "milk",
            "canonical_name": "milk",
            "confidence": 0.96,
            "changed": True,
            "reason": "Corrected typo and removed brand",
        }
    )
    matcher = ProductMatcher(api_key="test-key")
    matcher._client = SimpleNamespace(models=models)

    result = matcher.normalize_query(normalize_request())

    assert result.search_query == "milk"
    assert result.changed is True
    assert models.call["contents"][0] == NORMALIZE_PROMPT
    assert models.call["config"].temperature == 0.0
    assert models.call["config"].response_json_schema == NORMALIZE_RESPONSE_SCHEMA


@pytest.mark.parametrize(
    ("source", "unsafe_query"),
    [
        ("Apple juice 1L", "apples"),
        ("Milk powdr", "milk"),
        ("Sugar-free mango drink", "mango drink"),
        ("Baby formula", "milk"),
    ],
)
def test_normalization_keeps_original_when_product_form_is_dropped(
    source, unsafe_query
):
    result = NormalizeShoppingQueryResponse(
        search_query=unsafe_query,
        canonical_name=unsafe_query,
        confidence=0.99,
        changed=True,
        reason="unsafe mocked response",
    )

    validated = ProductMatcher.validate_normalization(normalize_request(source), result)

    assert validated.search_query == source
    assert validated.changed is False
    assert validated.confidence == 0


def test_normalization_allows_retained_product_form():
    result = NormalizeShoppingQueryResponse(
        search_query="apple juice",
        canonical_name="apple juice",
        confidence=0.95,
        changed=True,
        reason="Corrected spelling",
    )

    validated = ProductMatcher.validate_normalization(
        normalize_request("Nestle apple juce"), result
    )

    assert validated.search_query == "apple juice"
    assert validated.changed is True
