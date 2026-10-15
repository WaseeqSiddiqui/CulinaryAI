from fastapi import HTTPException
import pytest

from app.models.schemas import (
    MatchProductRequest,
    MatchProductResponse,
    ProductCandidateInput,
)
from app.services.product_matcher import ProductMatcher


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
