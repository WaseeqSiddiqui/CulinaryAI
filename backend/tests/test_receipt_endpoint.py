import io
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from PIL import Image

from app.main import app, vision_service
from app.models.vision_schemas import GeminiReceiptItem, GeminiReceiptResponse
from app.services.gemini_service import ScanRateLimiter


def create_test_image_bytes(format="JPEG", color="white", size=(200, 200)) -> bytes:
    img = Image.new("RGB", size, color=color)
    buffer = io.BytesIO()
    img.save(buffer, format=format)
    return buffer.getvalue()


@pytest.fixture
def client():
    return TestClient(app)


@pytest.fixture(autouse=True)
def reset_rate_limiter():
    vision_service.rate_limiter.reset()


def test_validation_total_quantity_calculation():
    """Validates total_qty = count * pack_size, or defaults count to 1 if pack_size exists."""
    gemini_resp = GeminiReceiptResponse(
        store_name="Metro Cash & Carry",
        date="2026-10-14",
        currency="PKR",
        receipt_total=1050.0,
        discounts_total=50.0,
        items=[
            # count=2, pack_size=500g -> total_qty=1000, unit='g'
            GeminiReceiptItem(
                raw_text="2 X CHICKEN BREAST 500G 600",
                name="Chicken Breast",
                pack_size=500.0,
                unit="g",
                count=2.0,
                line_price=600.0,
                is_food=True,
                confidence=0.98,
            ),
            # count=null, pack_size=1.5 -> total_qty=1.5, count defaulted to 1
            GeminiReceiptItem(
                raw_text="WATERMELON 1.5KG 300",
                name="Watermelon",
                pack_size=1.5,
                unit="kg",
                count=None,
                line_price=300.0,
                is_food=True,
                confidence=0.95,
            ),
            # count=3, pack_size=null -> total_qty=3, unit='pcs'
            GeminiReceiptItem(
                raw_text="3 X APPLE LOOSE 150",
                name="Apple",
                pack_size=None,
                unit=None,
                count=3.0,
                line_price=150.0,
                is_food=True,
                confidence=0.95,
            ),
            # count=null, pack_size=null -> total_qty=1, needs_review=True
            GeminiReceiptItem(
                raw_text="SPINACH BUNDLE 50",
                name="Spinach",
                pack_size=None,
                unit=None,
                count=None,
                line_price=50.0,
                is_food=True,
                confidence=0.90,
            ),
        ],
    )

    validated = vision_service._validate_and_enrich_receipt(
        gemini_response=gemini_resp,
        image_hash="fakehash123",
    )

    items = validated.items
    assert len(items) == 4

    # Item 1: Chicken Breast
    assert items[0].count == 2.0
    assert items[0].pack_size == 500.0
    assert items[0].total_qty == 1000.0
    assert items[0].unit == "g"
    assert items[0].storage_zone in ("Fridge", "Freezer")
    assert not items[0].needs_review

    # Item 2: Watermelon (loose weighed produce)
    assert items[1].count == 1.0
    assert items[1].pack_size == 1.5
    assert items[1].total_qty == 1.5
    assert items[1].unit == "kg"
    assert not items[1].needs_review

    # Item 3: Apple (count only)
    assert items[2].count == 3.0
    assert items[2].total_qty == 3.0
    assert items[2].unit == "pcs"
    assert not items[2].needs_review

    # Item 4: Spinach (missing quantities)
    assert items[3].count is None
    assert items[3].total_qty == 1.0
    assert items[3].needs_review is True
    assert any("missing quantity" in r.lower() for r in items[3].review_reasons)


def test_receipt_total_mismatch_flagged():
    """Flags receipt if sum(line_price) - discounts differs from receipt_total by > 5%."""
    # Sum of items = 500, discounts = 0, receipt_total = 1000 (diff = 50% > 5%)
    gemini_resp = GeminiReceiptResponse(
        store_name="Supermarket",
        receipt_total=1000.0,
        discounts_total=0.0,
        items=[
            GeminiReceiptItem(
                raw_text="MILK 1L 250",
                name="Milk",
                pack_size=1.0,
                unit="L",
                count=1.0,
                line_price=250.0,
                is_food=True,
                confidence=0.99,
            ),
            GeminiReceiptItem(
                raw_text="BREAD 250",
                name="Bread",
                pack_size=1.0,
                unit="pcs",
                count=1.0,
                line_price=250.0,
                is_food=True,
                confidence=0.99,
            ),
        ],
    )

    validated = vision_service._validate_and_enrich_receipt(
        gemini_response=gemini_resp,
        image_hash="hash_mismatch",
    )

    assert validated.calculated_items_total == 500.0
    assert validated.receipt_total == 1000.0
    assert validated.total_mismatch_warning is True
    assert validated.total_difference_percent == 50.0


def test_receipt_total_match_within_tolerance():
    """Within 5% difference does NOT flag warning."""
    # Sum = 980, discounts = 0, receipt_total = 1000 (diff = 2% <= 5%)
    gemini_resp = GeminiReceiptResponse(
        store_name="Supermarket",
        receipt_total=1000.0,
        discounts_total=0.0,
        items=[
            GeminiReceiptItem(
                raw_text="ITEM A 980",
                name="Milk",
                pack_size=1.0,
                unit="L",
                count=1.0,
                line_price=980.0,
                is_food=True,
                confidence=0.99,
            ),
        ],
    )

    validated = vision_service._validate_and_enrich_receipt(
        gemini_response=gemini_resp,
        image_hash="hash_ok",
    )

    assert validated.total_mismatch_warning is False
    assert validated.total_difference_percent == 2.0


def test_reject_negative_values_and_absurd_quantities():
    """Negative values and absurd quantities are rejected or flagged for review."""
    gemini_resp = GeminiReceiptResponse(
        store_name="Test Store",
        receipt_total=100.0,
        items=[
            GeminiReceiptItem(
                raw_text="NEG ITEM -50",
                name="Eggs",
                pack_size=-12.0,
                count=-2.0,
                line_price=-50.0,
                is_food=True,
                confidence=0.95,
            ),
            GeminiReceiptItem(
                raw_text="ABSURD ITEM",
                name="Rice",
                pack_size=999999.0,
                count=900.0,
                line_price=5000000.0,
                is_food=True,
                confidence=0.95,
            ),
        ],
    )

    validated = vision_service._validate_and_enrich_receipt(
        gemini_response=gemini_resp,
        image_hash="hash_absurd",
    )

    # Item 1: Negative values
    item1 = validated.items[0]
    assert item1.line_price == 50.0
    assert item1.count == 2.0
    assert item1.pack_size == 12.0
    assert item1.needs_review is True

    # Item 2: Absurd quantities
    item2 = validated.items[1]
    assert item2.needs_review is True
    assert any("absurd" in r.lower() for r in item2.review_reasons)


def test_catalog_matching_with_aliases_and_embedding():
    """Matches alias table first, then catalog exact/embedding, and flags low similarity."""
    catalog = vision_service.catalog

    # 1. Household alias match
    alias_match = catalog.match(
        name="desi murghi",
        raw_text="DESI MURGHI 1KG",
        household_aliases={"desi murghi": "Whole Chicken"},
    )
    assert alias_match.matched_name == "Whole Chicken"
    assert alias_match.confidence == 1.0
    assert not alias_match.needs_review

    # 2. Known catalog alias match (tamatar -> Tomato)
    tamatar_match = catalog.match(name="tamatar", raw_text="TAMATAR 2KG")
    assert tamatar_match.matched_name == "Tomato"
    assert tamatar_match.storage_zone == "Fridge"
    assert not tamatar_match.needs_review

    # 3. Completely unrecognized item
    unknown_match = catalog.match(name="Xyz789 Nonexistent Organic Powder")
    assert unknown_match.needs_review is True


def test_rate_limiting_enforces_max_scans():
    """Rate limiter allows 20 scans per user and blocks the 21st scan with HTTP 429."""
    limiter = ScanRateLimiter(max_per_day=20)
    user_id = "test_user_rate"

    for i in range(20):
        limiter.check_and_record(user_id)
        assert limiter.get_remaining(user_id) == 19 - i

    with pytest.raises(HTTPException) as exc_info:
        limiter.check_and_record(user_id)
    assert exc_info.value.status_code == 429
    assert "Daily scan limit reached" in exc_info.value.detail


def test_parse_receipt_endpoint_with_mocked_gemini(client):
    """Tests the full POST /parse-receipt HTTP endpoint using a mocked Gemini response."""
    mock_gemini_resp = GeminiReceiptResponse(
        store_name="Carrefour Market",
        date="2026-10-15",
        currency="PKR",
        receipt_total=850.0,
        discounts_total=0.0,
        items=[
            GeminiReceiptItem(
                raw_text="MILK 1L 280.00",
                name="Milk",
                pack_size=1.0,
                unit="L",
                count=1.0,
                line_price=280.0,
                is_food=True,
                confidence=0.99,
            ),
            GeminiReceiptItem(
                raw_text="EGGS DOZEN 350.00",
                name="Eggs",
                pack_size=12.0,
                unit="pcs",
                count=1.0,
                line_price=350.0,
                is_food=True,
                confidence=0.98,
            ),
            GeminiReceiptItem(
                raw_text="BREAD LARGE 220.00",
                name="Bread",
                pack_size=1.0,
                unit="pcs",
                count=1.0,
                line_price=220.0,
                is_food=True,
                confidence=0.97,
            ),
            GeminiReceiptItem(
                raw_text="PLASTIC BAG 10.00",
                name="Plastic Bag",
                pack_size=None,
                unit="pcs",
                count=1.0,
                line_price=10.0,
                is_food=False,
                confidence=0.99,
            ),
        ],
    )

    image_bytes = create_test_image_bytes()

    with patch.object(
        vision_service, "_invoke_gemini_receipt", return_value=mock_gemini_resp
    ):
        response = client.post(
            "/parse-receipt",
            files={"file": ("receipt.jpg", image_bytes, "image/jpeg")},
            headers={"X-User-Id": "user_stage1_test"},
        )

        assert response.status_code == 200
        data = response.json()

        assert data["store_name"] == "Carrefour Market"
        assert data["date"] == "2026-10-15"
        assert data["receipt_total"] == 850.0
        assert len(data["items"]) == 4

        # Food item check
        milk = next(item for item in data["items"] if item["name"] == "Milk")
        assert milk["matched_ingredient"] == "Milk"
        assert milk["total_qty"] == 1.0
        assert milk["unit"] == "L"
        assert milk["is_food"] is True

        # Non-food check
        bag = next(item for item in data["items"] if item["name"] == "Plastic Bag")
        assert bag["is_food"] is False


def test_parse_receipt_unreadable_image(client):
    """Corrupted / unreadable image bytes return HTTP 400."""
    corrupted_bytes = b"NotAValidImageByteSequence"
    response = client.post(
        "/parse-receipt",
        files={"file": ("corrupted.jpg", corrupted_bytes, "image/jpeg")},
        headers={"X-User-Id": "user_corrupt_test"},
    )
    assert response.status_code == 400
    assert "not a valid or readable image" in response.json()["detail"].lower()
