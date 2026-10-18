import pytest

from app.services.ingredient_catalog import IngredientCatalogService


@pytest.fixture
def catalog() -> IngredientCatalogService:
    return IngredientCatalogService()


@pytest.mark.parametrize(
    ("item_name", "expected_zone"),
    [
        ("National Red Chili", "Spice Rack"),
        ("Frozen Chicken Nuggets", "Freezer"),
        ("Fish Masala", "Spice Rack"),
        ("Chicken Masala", "Spice Rack"),
        ("Coriander Seeds", "Spice Rack"),
        ("Chilli Garlic Sauce", "Fridge"),
        ("Dalda Banaspati", "Pantry Shelf"),
        ("Canned Tomatoes", "Pantry Shelf"),
    ],
)
def test_form_modifier_wins_over_base_ingredient(
    catalog: IngredientCatalogService,
    item_name: str,
    expected_zone: str,
) -> None:
    result = catalog.match(name=item_name, raw_text=item_name)

    assert result.storage_zone == expected_zone
    assert result.needs_review is False


@pytest.mark.parametrize("item_name", ["Surf Excel", "Detergent", "Toothpaste"])
def test_unknown_items_never_inherit_an_arbitrary_catalog_zone(
    catalog: IngredientCatalogService,
    item_name: str,
) -> None:
    result = catalog.match(name=item_name, raw_text=item_name)

    assert result.storage_zone == "Pantry Shelf"
    assert result.needs_review is True
    assert result.method == "below_threshold"


def test_word_boundaries_do_not_match_dal_inside_dalda(
    catalog: IngredientCatalogService,
) -> None:
    result = catalog.match(name="Dalda Banaspati", raw_text="DALDA BANASPATI 1KG")

    assert result.matched_name == "Ghee"
    assert result.storage_zone == "Pantry Shelf"
