import pytest

from app.services.embedding_service import HashEmbeddingService
from app.services.recipe_repository import VerifiedRecipeRepository


def test_hash_embeddings_are_deterministic_and_normalized() -> None:
    embedder = HashEmbeddingService()
    first = embedder.embed("chicken rice garlic")
    second = embedder.embed("chicken rice garlic")

    assert first == second
    assert embedder.similarity(first, second) == pytest.approx(1.0)


def test_repository_retrieves_a_relevant_verified_recipe() -> None:
    results = VerifiedRecipeRepository().search(
        "chicken basmati rice garlic", limit=1
    )

    assert results[0].recipe["recipe_id"] == "rec_chicken_rice"
    assert results[0].score > 0
