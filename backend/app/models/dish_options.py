from datetime import date
from typing import Annotated, Literal

from pydantic import BaseModel, Field, StringConstraints

from app.models.recipe_discovery import DiscoveredRecipe
from app.models.schemas import PantryItemInput

SearchText = Annotated[str, StringConstraints(strip_whitespace=True, min_length=2, max_length=120, pattern=r"^[^\x00-\x1f\x7f]+$")]


class DishOptionsRequest(BaseModel):
    dish: SearchText
    pantry_items: list[PantryItemInput] = Field(default_factory=list, max_length=500)
    reference_date: date = Field(default_factory=date.today)


class DishOptionsResponse(BaseModel):
    dish: str
    status: Literal["ready", "missing", "check_quantities", "recipe_not_found"]
    recipe: DiscoveredRecipe | None = None
    message: str
    quantities_note: str = "Inventory is compared with the source recipe's listed amounts. Check its portions before cooking."


class RestaurantSearchRequest(BaseModel):
    dish: SearchText
    area: SearchText


class RestaurantOption(BaseModel):
    name: str
    url: str
    summary: str
    source: str = "Foodpanda"


class RestaurantSearchResponse(BaseModel):
    dish: str
    area: str
    restaurants: list[RestaurantOption] = Field(default_factory=list)
    message: str
    provider: str = "Tavily"
    availability_note: str = "Search matches for this area. Check the menu, price and delivery coverage before ordering."
