from __future__ import annotations

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    StrictInt,
    field_validator,
    model_validator,
)


class PantryItemInput(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    quantity: float = Field(default=1, ge=0)
    unit: str = Field(default="pcs", min_length=1, max_length=24)

    @field_validator("name", "unit")
    @classmethod
    def clean_text(cls, value: str) -> str:
        return value.strip()


class Ingredient(BaseModel):
    name: str
    quantity: float = Field(gt=0)
    unit: str


class CookingStep(BaseModel):
    step_number: int = Field(ge=1)
    instruction: str
    timer_seconds: int = Field(default=0, ge=0)


class GeneratePlanRequest(BaseModel):
    question: str = Field(default="", max_length=300)
    pantry_items: list[PantryItemInput] = Field(default_factory=list)
    servings: int = Field(default=4, ge=1, le=12)
    meal_count: int = Field(default=3, ge=1, le=7)
    dietary_preferences: list[str] = Field(default_factory=list)
    avoid_ingredients: list[str] = Field(default_factory=list)
    max_cook_time_minutes: int | None = Field(default=None, ge=5, le=240)
    meals_per_day: int = Field(default=3, ge=1, le=6)
    target_calories_per_person_per_day: int | None = Field(
        default=None, ge=800, le=6000
    )
    pantry_first: bool = True

    @field_validator("question")
    @classmethod
    def clean_question(cls, value: str) -> str:
        return value.strip()

    @field_validator("dietary_preferences")
    @classmethod
    def normalize_preferences(cls, values: list[str]) -> list[str]:
        return [value.strip().lower() for value in values if value.strip()]

    @field_validator("avoid_ingredients")
    @classmethod
    def normalize_avoids(cls, values: list[str]) -> list[str]:
        return [value.strip().lower() for value in values if value.strip()]


class MealPlanRecipe(BaseModel):
    recipe_id: str
    name: str
    cuisine: str
    cook_time_minutes: int
    servings: int
    pantry_match_percent: int
    retrieval_score: float
    ingredients_required: list[Ingredient]
    available_ingredients: list[str]
    missing_ingredients: list[str]
    steps: list[CookingStep]
    source: str
    calories_per_serving: int = Field(default=0, ge=0)


class GeneratePlanResponse(BaseModel):
    meals: list[MealPlanRecipe]
    pantry_item_count: int
    retrieval_method: str = "verified-recipe-hash-embedding-v1"
    pantry_checked: bool = True
    requested_servings: int = 4
    target_calories_per_meal: int | None = None


class InstructionRequest(BaseModel):
    recipe_id: str = Field(min_length=1)
    servings: int = Field(default=4, ge=1, le=12)


class InstructionResponse(BaseModel):
    recipe_id: str
    recipe_name: str
    servings: int
    ingredients_required: list[Ingredient]
    steps: list[CookingStep]
    completion_prompt: str = "Have you finished cooking this meal?"


class HealthResponse(BaseModel):
    status: str
    indexed_recipes: int


class ProductCandidateInput(BaseModel):
    name: str = Field(min_length=1, max_length=240)
    size: str | None = Field(default=None, max_length=80)
    price: float = Field(ge=0)
    in_stock: bool


class MatchProductRequest(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    quantity: float = Field(gt=0, le=10000)
    unit: str = Field(min_length=1, max_length=24)
    candidates: list[ProductCandidateInput] = Field(min_length=1, max_length=8)


class MatchProductResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    chosen_index: StrictInt | None = Field(
        description="Zero-based index into the candidates array, or null for no match."
    )
    units_to_buy: StrictInt | None = Field(
        ge=1,
        le=10,
        description="Number of packs to add, or null when chosen_index is null.",
    )
    confidence: float = Field(ge=0, le=1)
    reason: str = Field(min_length=1, max_length=500)

    @field_validator("reason")
    @classmethod
    def clean_reason(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("reason must not be blank")
        return value

    @model_validator(mode="after")
    def choice_and_units_must_align(self):
        if (self.chosen_index is None) != (self.units_to_buy is None):
            raise ValueError(
                "chosen_index and units_to_buy must either both be null or both be set"
            )
        return self


class NormalizeShoppingQueryRequest(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    quantity: float = Field(gt=0, le=10000)
    unit: str = Field(min_length=1, max_length=24)

    @field_validator("name", "unit")
    @classmethod
    def clean_query_text(cls, value: str) -> str:
        return value.strip()


class NormalizeShoppingQueryResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    search_query: str = Field(min_length=1, max_length=120)
    canonical_name: str = Field(min_length=1, max_length=120)
    confidence: float = Field(ge=0, le=1)
    changed: bool
    reason: str = Field(min_length=1, max_length=500)

    @field_validator("search_query", "canonical_name", "reason")
    @classmethod
    def clean_normalized_text(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("normalized text must not be blank")
        return value


class ChefChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=1000)
    pantry_items: list[PantryItemInput] = Field(default_factory=list)


class ChefChatResponse(BaseModel):
    reply: str

