from datetime import date
from typing import Literal

from pydantic import BaseModel, Field

from app.models.schemas import GeneratePlanRequest


class RecipeDiscoveryRequest(GeneratePlanRequest):
    reference_date: date = Field(default_factory=date.today)
    requested_date: date | None = None


class IngredientCheck(BaseModel):
    name: str
    measure: str
    quantity: float | None = None
    unit: str = ""
    status: Literal["available", "missing", "insufficient", "check_quantity"]
    available_quantity: float | None = None
    missing_quantity: float | None = None


class DiscoveredRecipe(BaseModel):
    recipe_id: str
    name: str
    cuisine: str = ""
    category: str = ""
    image_url: str = ""
    source: str = "TheMealDB"
    source_url: str
    original_source_url: str | None = None
    ingredients: list[IngredientCheck]
    pantry_match_percent: int
    can_cook_now: bool
    servings: int | None = None
    cook_time_minutes: int | None = None


class RecipeDiscoveryResponse(BaseModel):
    meals: list[DiscoveredRecipe] = Field(default_factory=list)
    pantry_item_count: int
    planning_date: date
    retrieval_method: str = "themealdb-live-ingredient-search"
    message: str
    excluded_expired_items: list[str] = Field(default_factory=list)
    searched_ingredients: list[str] = Field(default_factory=list)
    checked_recipe_count: int = 0
    provider: str = "TheMealDB"
    provider_url: str = "https://www.themealdb.com"
    source_quantities_note: str = (
        "Matches use the recipe's listed quantities. Serving counts and cooking "
        "times are not supplied by this provider; check the recipe before cooking "
        "for your household. No salt, oil or other staples are assumed."
    )
