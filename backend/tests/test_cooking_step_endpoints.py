import io
from unittest.mock import patch

from fastapi.testclient import TestClient
from PIL import Image

from app.main import app, vision_service
from app.models.vision_schemas import (
    CookingStepValidationResponse,
    StepExplanationResponse,
)


def _sample_image() -> bytes:
    buffer = io.BytesIO()
    Image.new("RGB", (100, 100), color="goldenrod").save(buffer, format="JPEG")
    return buffer.getvalue()


def test_step_explanation_endpoint() -> None:
    client = TestClient(app)
    explanation = StepExplanationResponse(
        recipe_title="Caramelized Onion Pasta",
        step_number=2,
        action="Sauté sliced onions until golden brown.",
        overview="Cook slowly for even browning.",
        heat_level="Medium-low",
        pace="Slowly",
        estimated_duration="8–12 minutes (estimate)",
        technique="Stir every 1–2 minutes.",
        visual_cues=["Uniform honey-amber color"],
        texture_and_aroma="Soft and sweet-smelling",
        precautions=["Do not use high heat"],
        completion_criteria="Uniformly golden, soft, and sweet-smelling",
        pro_tip="Spread the onions evenly.",
    )
    with patch.object(vision_service, "get_step_explanation", return_value=explanation):
        response = client.post(
            "/step-explanation",
            json={
                "recipe_title": "Caramelized Onion Pasta",
                "step_number": 2,
                "step_instruction": "Sauté sliced onions in olive oil until golden brown and sweet.",
            },
        )

    assert response.status_code == 200
    data = response.json()
    assert data["recipe_title"] == "Caramelized Onion Pasta"
    assert data["step_number"] == 2
    assert data["action"] != ""
    assert data["technique"] != ""
    assert data["estimated_duration"] != ""
    assert len(data["visual_cues"]) >= 1
    assert data["heat_level"] != ""
    assert data["completion_criteria"] != ""
    assert data["pro_tip"] != ""


def test_cooking_step_chat_endpoint_preserves_context() -> None:
    client = TestClient(app)
    with patch.object(
        vision_service,
        "chat_cooking_step",
        return_value="Cook until the onions are evenly amber and sweet-smelling.",
    ) as mocked_chat:
        response = client.post(
            "/cooking-step-chat",
            json={
                "recipe_title": "Biryani",
                "step_number": 3,
                "step_instruction": "Fry sliced onions until deep golden brown.",
                "message": "What is the requirement for golden brown onions?",
                "conversation_history": [
                    {"role": "user", "content": "I lowered the heat."}
                ],
                "adjustments": ["Heat lowered"],
                "dietary_restrictions": ["Nut-free"],
            },
        )

    assert response.status_code == 200
    assert len(response.json()["reply"]) > 10
    kwargs = mocked_chat.call_args.kwargs
    assert kwargs["conversation_history"][0]["content"] == "I lowered the heat."
    assert kwargs["adjustments"] == ["Heat lowered"]


def test_validate_cooking_step_endpoint() -> None:
    client = TestClient(app)
    mock_validation = CookingStepValidationResponse(
        status="ready",
        headline="Golden Brown & Ready!",
        feedback="The onions have reached a rich, uniform golden brown color.",
        action_suggestion="Remove from heat to prevent scorching.",
        visual_observations=[
            "Uniform deep amber caramelization",
            "Even gloss without burnt black edges",
        ],
        confidence=0.92,
        image_sufficient=True,
        image_hash="abc123hash",
    )

    with patch.object(vision_service, "validate_cooking_step", return_value=mock_validation):
        response = client.post(
            "/validate-cooking-step",
            files={"file": ("onions.jpg", _sample_image(), "image/jpeg")},
            data={
                "recipe_title": "Classic French Onion Soup",
                "step_number": "1",
                "step_instruction": "Cook sliced onions until golden brown.",
                "user_question": "Is this what golden brown onion is?",
                "user_id": "test_chef_1",
            },
        )

    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ready"
    assert "Golden Brown" in data["headline"]
    assert len(data["visual_observations"]) == 2
    assert data["confidence"] == 0.92
    assert data["image_sufficient"] is True
    assert "temperature" in data["safety_note"].lower()


def test_offline_visual_fallback_never_claims_image_was_seen() -> None:
    with patch.object(vision_service, "_get_client", side_effect=RuntimeError("offline")):
        result = vision_service.validate_cooking_step(
            image_bytes=_sample_image(),
            mime_type="image/jpeg",
            recipe_title="Biryani",
            step_number=1,
            step_instruction="Brown the onions.",
            user_id="offline-safety-test",
        )

    assert result.status == "unable_to_assess"
    assert result.image_sufficient is False
    assert result.confidence == 0
    assert "cannot verify" in result.safety_note.lower()
