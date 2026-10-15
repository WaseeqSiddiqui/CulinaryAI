import io
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.main import app, vision_service
from app.models.vision_schemas import (
    ExistingPantryItem,
    GeminiFridgeItem,
    GeminiFridgeScan,
)
from app.services.fridge_reconciler import FridgeReconciler


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


def test_fridge_reconciliation_exact_and_within_tolerance():
    """Items matching within tolerance are marked verified with a timestamp."""
    reconciler = FridgeReconciler()

    pantry_items = [
        ExistingPantryItem(id="p1", name="Eggs", quantity=4.0, unit="pcs", location="Fridge"),
        ExistingPantryItem(id="p2", name="Cheddar Cheese", quantity=1.0, unit="pcs", location="Fridge"),
    ]

    detected_scan = GeminiFridgeScan(
        items=[
            GeminiFridgeItem(name="Eggs", count=4, confidence=0.98),
            GeminiFridgeItem(name="Cheddar Cheese", count=1, confidence=0.95),
        ]
    )

    result = reconciler.reconcile(detected_scan, pantry_items)

    assert result.verified_count == 2
    assert result.mismatch_count == 0
    assert result.new_items_count == 0

    assert result.reconciled_items[0].status == "verified"
    assert result.reconciled_items[0].verified_at is not None
    assert result.reconciled_items[0].matched_pantry_id == "p1"


def test_fridge_reconciliation_count_mismatch():
    """Mismatched countable items generate questions and do NOT change stock silently."""
    reconciler = FridgeReconciler()

    pantry_items = [
        ExistingPantryItem(id="p1", name="Eggs", quantity=6.0, unit="pcs", location="Fridge"),
    ]

    # Camera only sees 2 eggs remaining
    detected_scan = GeminiFridgeScan(
        items=[
            GeminiFridgeItem(name="Eggs", count=2, confidence=0.95),
        ]
    )

    result = reconciler.reconcile(detected_scan, pantry_items)

    assert result.mismatch_count == 1
    reconciled = result.reconciled_items[0]
    assert reconciled.status == "mismatch"
    assert reconciled.current_quantity == 6.0
    assert reconciled.suggested_quantity == 2.0
    assert reconciled.estimated is True
    assert "detected 2 pcs" in reconciled.question.lower()
    assert "pantry lists 6 pcs" in reconciled.question.lower()


def test_fridge_reconciliation_fill_level_mismatch():
    """Opened packaged liquids with fill level generate clarification questions."""
    reconciler = FridgeReconciler()

    pantry_items = [
        ExistingPantryItem(id="p1", name="Milk", quantity=1.0, unit="L", location="Fridge"),
    ]

    # Detected carton is half empty (fill_level = 0.5)
    detected_scan = GeminiFridgeScan(
        items=[
            GeminiFridgeItem(
                name="Milk",
                fill_level=0.5,
                label_size_text="1L",
                confidence=0.92,
            ),
        ]
    )

    result = reconciler.reconcile(detected_scan, pantry_items)

    assert result.mismatch_count == 1
    reconciled = result.reconciled_items[0]
    assert reconciled.status == "mismatch"
    assert reconciled.suggested_quantity == 0.5
    assert reconciled.estimated is True
    assert "50%" in reconciled.question
    assert "0.5" in reconciled.question


def test_fridge_reconciliation_item_not_in_ledger():
    """Detected items not in household ledger generate 'add this item?' questions."""
    reconciler = FridgeReconciler()

    pantry_items = [
        ExistingPantryItem(id="p1", name="Milk", quantity=1.0, unit="L", location="Fridge"),
    ]

    # Camera sees Yogurt, which is not in pantry
    detected_scan = GeminiFridgeScan(
        items=[
            GeminiFridgeItem(name="Greek Yogurt", count=2, confidence=0.96),
        ]
    )

    result = reconciler.reconcile(detected_scan, pantry_items)

    assert result.new_items_count == 1
    reconciled = result.reconciled_items[0]
    assert reconciled.status == "new_item"
    assert reconciled.suggested_quantity == 2.0
    assert reconciled.estimated is True
    assert "not in your kitchen stock" in reconciled.question.lower()


def test_fridge_unseen_ledger_items_not_deleted():
    """Pantry items in the ledger that are NOT seen in the photo are NEVER deleted or reduced."""
    reconciler = FridgeReconciler()

    pantry_items = [
        ExistingPantryItem(id="p1", name="Milk", quantity=1.0, unit="L", location="Fridge"),
        ExistingPantryItem(id="p2", name="Butter", quantity=200.0, unit="g", location="Fridge"),
        ExistingPantryItem(id="p3", name="Hidden Cheese", quantity=1.0, unit="pcs", location="Fridge"),
    ]

    # Camera photo only sees Milk
    detected_scan = GeminiFridgeScan(
        items=[
            GeminiFridgeItem(name="Milk", count=1, confidence=0.95),
        ]
    )

    result = reconciler.reconcile(detected_scan, pantry_items)

    assert len(result.reconciled_items) == 1
    assert result.reconciled_items[0].matched_pantry_id == "p1"
    # p2 and p3 are completely untouched


def test_post_scan_fridge_endpoint(client):
    """Tests the POST /scan-fridge HTTP API with multipart upload and mocked Gemini."""
    mock_scan = GeminiFridgeScan(
        items=[
            GeminiFridgeItem(name="Eggs", count=4, confidence=0.98),
            GeminiFridgeItem(name="Apple", count=2, confidence=0.91),
        ]
    )

    pantry_json = '[{"id": "p_egg", "name": "Eggs", "quantity": 4.0, "unit": "pcs", "location": "Fridge"}]'
    image_bytes = create_test_image_bytes()

    with patch.object(vision_service, "_invoke_gemini_fridge", return_value=mock_scan):
        response = client.post(
            "/scan-fridge",
            files={"file": ("fridge.jpg", image_bytes, "image/jpeg")},
            data={"pantry_items": pantry_json, "user_id": "test_fridge_user"},
        )

        assert response.status_code == 200
        data = response.json()

        assert len(data["detected_items"]) == 2
        assert len(data["reconciled_items"]) == 2
        assert data["verified_count"] == 1
        assert data["new_items_count"] == 1

        verified_item = next(it for it in data["reconciled_items"] if it["status"] == "verified")
        assert verified_item["matched_name"] == "Eggs"
        assert verified_item["verified_at"] is not None

        new_item = next(it for it in data["reconciled_items"] if it["status"] == "new_item")
        assert new_item["matched_name"] == "Apple"
        assert new_item["estimated"] is True
