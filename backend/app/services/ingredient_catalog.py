from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from app.services.embedding_service import HashEmbeddingService


@dataclass(frozen=True)
class CatalogIngredient:
    name: str
    category: str
    default_unit: str
    storage_zone: str  # 'Fridge', 'Freezer', 'Pantry Shelf', 'Spice Rack'
    aliases: tuple[str, ...] = ()


# Default rich ingredient database matching the Flutter app's FoodImageService & culinary rules
DEFAULT_INGREDIENTS: list[CatalogIngredient] = [
    # Dairy & Eggs -> Fridge
    CatalogIngredient("Milk", "Dairy", "L", "Fridge", ("whole milk", "fresh milk", "olpers", "milk pack", "doodh")),
    CatalogIngredient("Eggs", "Dairy & Eggs", "pcs", "Fridge", ("egg", "anda", "desi eggs", "white eggs", "dozen eggs")),
    CatalogIngredient("Butter", "Dairy", "g", "Fridge", ("butter", "makhan", "unsalted butter", "salted butter")),
    CatalogIngredient("Yogurt", "Dairy", "g", "Fridge", ("curd", "dahi", "greek yogurt", "plain yogurt")),
    CatalogIngredient("Cheddar Cheese", "Dairy", "g", "Fridge", ("cheese", "cheddar", "processed cheese")),
    CatalogIngredient("Mozzarella Cheese", "Dairy", "g", "Fridge", ("mozzarella", "pizza cheese")),
    CatalogIngredient("Heavy Cream", "Dairy", "ml", "Fridge", ("cream", "malai", "whipping cream", "dairy cream")),
    CatalogIngredient("Paneer", "Dairy", "g", "Fridge", ("paneer", "cottage cheese")),
    CatalogIngredient("Mayonnaise", "Condiments", "g", "Fridge", ("mayo", "real mayonnaise", "garlic mayo")),
    
    # Meats & Poultry -> Fridge / Freezer
    CatalogIngredient("Chicken Breast", "Meat & Poultry", "kg", "Fridge", ("chicken", "boneless chicken", "chicken fillet")),
    CatalogIngredient("Chicken Mince", "Meat & Poultry", "kg", "Fridge", ("chicken keema", "minced chicken")),
    CatalogIngredient("Whole Chicken", "Meat & Poultry", "kg", "Fridge", ("broiler chicken", "desi chicken", "cut chicken")),
    CatalogIngredient("Beef Steak", "Meat & Poultry", "kg", "Fridge", ("beef", "beef undercut", "beef boneless", "gosht")),
    CatalogIngredient("Beef Mince", "Meat & Poultry", "kg", "Fridge", ("beef keema", "qeema")),
    CatalogIngredient("Mutton", "Meat & Poultry", "kg", "Fridge", ("lamb", "goat meat", "mutton mix")),
    CatalogIngredient("Fish Fillet", "Seafood", "kg", "Freezer", ("fish", "salmon", "tilapia", "raw fish", "machli")),
    CatalogIngredient("Prawns", "Seafood", "kg", "Freezer", ("shrimp", "jheenga")),
    CatalogIngredient("Frozen Peas", "Frozen Food", "kg", "Freezer", ("peas", "matar", "green peas")),
    CatalogIngredient("Frozen Fries", "Frozen Food", "kg", "Freezer", ("french fries", "potato fries", "potatoes frozen")),
    CatalogIngredient("Ice Cream", "Dessert", "ml", "Freezer", ("kulfa", "vanilla ice cream", "chocolate ice cream")),
    
    # Fresh Produce -> Fridge / Pantry Shelf
    CatalogIngredient("Tomato", "Produce", "kg", "Fridge", ("tomatoes", "tom loose", "tamatar", "cherry tomatoes")),
    CatalogIngredient("Onion", "Produce", "kg", "Pantry Shelf", ("onions", "pyaz", "red onion", "yellow onion", "white onion")),
    CatalogIngredient("Potato", "Produce", "kg", "Pantry Shelf", ("potatoes", "aloo", "russet potato")),
    CatalogIngredient("Garlic", "Produce", "g", "Pantry Shelf", ("lahsun", "garlic bulb", "peeled garlic")),
    CatalogIngredient("Ginger", "Produce", "g", "Fridge", ("adrak", "fresh ginger", "ginger root")),
    CatalogIngredient("Green Chilies", "Produce", "g", "Fridge", ("hari mirch", "green pepper", "chili")),
    CatalogIngredient("Carrot", "Produce", "kg", "Fridge", ("carrots", "gajar")),
    CatalogIngredient("Cucumber", "Produce", "kg", "Fridge", ("kheera", "english cucumber")),
    CatalogIngredient("Spinach", "Produce", "pcs", "Fridge", ("palak", "fresh spinach", "baby spinach")),
    CatalogIngredient("Bell Pepper", "Produce", "pcs", "Fridge", ("capsicum", "shimla mirch", "green bell pepper", "red bell pepper")),
    CatalogIngredient("Lemon", "Produce", "pcs", "Fridge", ("lemons", "lime", "nimbu", "lemon yellow")),
    CatalogIngredient("Banana", "Produce", "pcs", "Pantry Shelf", ("bananas", "kela", "dozen bananas")),
    CatalogIngredient("Apple", "Produce", "kg", "Fridge", ("apples", "saib", "red apple", "fuji apple")),
    CatalogIngredient("Orange", "Produce", "kg", "Fridge", ("oranges", "kino", "citrus")),
    CatalogIngredient("Coriander", "Produce", "pcs", "Fridge", ("cilantro", "dhaniya", "fresh coriander", "parsley")),
    CatalogIngredient("Mint", "Produce", "pcs", "Fridge", ("podina", "pudina", "fresh mint")),
    
    # Pantry Staples -> Pantry Shelf
    CatalogIngredient("Basmati Rice", "Grains", "kg", "Pantry Shelf", ("rice", "chawal", "super basmati", "brown rice", "jasmine rice")),
    CatalogIngredient("Wheat Flour", "Grains", "kg", "Pantry Shelf", ("flour", "atta", "chakki atta", "maida", "all purpose flour")),
    CatalogIngredient("Cooking Oil", "Oils", "L", "Pantry Shelf", ("vegetable oil", "canola oil", "sunflower oil", "tel")),
    CatalogIngredient("Olive Oil", "Oils", "ml", "Pantry Shelf", ("extra virgin olive oil", "pomace olive oil")),
    CatalogIngredient("Ghee", "Oils", "kg", "Pantry Shelf", ("desi ghee", "clarified butter", "banaspati ghee")),
    CatalogIngredient("Sugar", "Baking", "kg", "Pantry Shelf", ("white sugar", "cheeni", "cane sugar")),
    CatalogIngredient("Pasta", "Grains", "g", "Pantry Shelf", ("macaroni", "spaghetti", "penne", "fusilli")),
    CatalogIngredient("Noodles", "Grains", "pcs", "Pantry Shelf", ("instant noodles", "ramen", "maggi", "indomie", "knorr noodles")),
    CatalogIngredient("Lentils", "Pulses", "kg", "Pantry Shelf", ("daal", "dal", "moong daal", "masoor daal", "chana daal")),
    CatalogIngredient("Chickpeas", "Pulses", "kg", "Pantry Shelf", ("chana", "safaid chana", "garbanzo")),
    CatalogIngredient("Bread", "Bakery", "pcs", "Pantry Shelf", ("sandwich bread", "white bread", "brown bread", "loaf")),
    CatalogIngredient("Canned Tomatoes", "Canned Goods", "pcs", "Pantry Shelf", ("tomato puree", "tomato paste", "chopped tomatoes")),
    CatalogIngredient("Tomato Ketchup", "Condiments", "g", "Fridge", ("ketchup", "tomato sauce", "chili garlic sauce")),
    CatalogIngredient("Soy Sauce", "Condiments", "ml", "Pantry Shelf", ("dark soy sauce", "light soy sauce")),
    CatalogIngredient("Vinegar", "Condiments", "ml", "Pantry Shelf", ("white vinegar", "sirka", "apple cider vinegar")),
    CatalogIngredient("Tea", "Beverages", "g", "Pantry Shelf", ("chai", "black tea", "tapal", "lipton", "green tea")),
    CatalogIngredient("Coffee", "Beverages", "g", "Pantry Shelf", ("instant coffee", "nescafe", "ground coffee")),
    CatalogIngredient("Diet Cola", "Beverages", "pcs", "Fridge", ("cola", "coke", "pepsi", "soda", "diet coke")),
    CatalogIngredient("Mineral Water", "Beverages", "L", "Pantry Shelf", ("water", "drinking water", "nestle water")),

    # Spices -> Spice Rack
    CatalogIngredient("Salt", "Spices", "g", "Spice Rack", ("table salt", "iodized salt", "namak", "pink salt")),
    CatalogIngredient("Black Pepper", "Spices", "g", "Spice Rack", ("kali mirch", "black pepper powder", "peppercorns")),
    CatalogIngredient("Red Chili Powder", "Spices", "g", "Spice Rack", ("lal mirch", "chili powder", "cayenne")),
    CatalogIngredient("Turmeric", "Spices", "g", "Spice Rack", ("haldi", "turmeric powder")),
    CatalogIngredient("Cumin", "Spices", "g", "Spice Rack", ("zeera", "jeera", "cumin seeds", "ground cumin")),
    CatalogIngredient("Coriander Powder", "Spices", "g", "Spice Rack", ("dhaniya powder", "ground coriander")),
    CatalogIngredient("Garam Masala", "Spices", "g", "Spice Rack", ("mixed spices", "all spice powder")),
    CatalogIngredient("Cinnamon", "Spices", "g", "Spice Rack", ("dar cheeni", "cinnamon sticks")),
    CatalogIngredient("Cardamom", "Spices", "g", "Spice Rack", ("elaichi", "green cardamom")),
    CatalogIngredient("Cloves", "Spices", "g", "Spice Rack", ("laung", "clove")),
]


@dataclass
class MatchResult:
    matched_name: str
    confidence: float
    storage_zone: str
    unit: str
    needs_review: bool
    method: str


class IngredientCatalogService:
    def __init__(
        self,
        recipes_path: Path | None = None,
        embedder: HashEmbeddingService | None = None,
    ) -> None:
        self.embedder = embedder or HashEmbeddingService()
        self._ingredients: list[CatalogIngredient] = list(DEFAULT_INGREDIENTS)
        
        # Ingest ingredients from verified recipes if available
        recipe_data_path = recipes_path or (
            Path(__file__).resolve().parents[1] / "data" / "verified_recipes.json"
        )
        if recipe_data_path.exists():
            self._load_from_recipes(recipe_data_path)

        # Precompute vectors
        self._vectors = {
            ing.name: self.embedder.embed(self._ingredient_text(ing))
            for ing in self._ingredients
        }

    def _load_from_recipes(self, path: Path) -> None:
        try:
            with path.open("r", encoding="utf-8") as f:
                data = json.load(f)
            existing_names = {i.name.lower() for i in self._ingredients}
            for recipe in data.get("recipes", []):
                for req in recipe.get("ingredients_required", []):
                    name = req.get("name", "").strip().title()
                    if name and name.lower() not in existing_names:
                        unit = req.get("unit", "pcs")
                        # Infer zone
                        zone = self._infer_zone(name)
                        self._ingredients.append(
                            CatalogIngredient(
                                name=name,
                                category="General",
                                default_unit=unit,
                                storage_zone=zone,
                            )
                        )
                        existing_names.add(name.lower())
        except Exception:
            pass

    def _infer_zone(self, name: str) -> str:
        n = name.lower()
        if any(w in n for w in ("milk", "egg", "butter", "cheese", "yogurt", "chicken", "beef", "meat", "tomato", "salad", "spinach", "lemon")):
            return "Fridge"
        if any(w in n for w in ("frozen", "ice cream", "fish", "peas", "prawn")):
            return "Freezer"
        if any(w in n for w in ("salt", "pepper", "turmeric", "cumin", "masala", "cinnamon", "cardamom", "clove", "spice")):
            return "Spice Rack"
        return "Pantry Shelf"

    @staticmethod
    def _ingredient_text(ing: CatalogIngredient) -> str:
        return " ".join([ing.name, ing.category, " ".join(ing.aliases)]).lower()

    def match(
        self,
        name: str,
        raw_text: str = "",
        household_aliases: dict[str, str] | None = None,
        threshold: float = 0.60,
    ) -> MatchResult:
        cleaned_raw = raw_text.strip().lower()
        cleaned_name = name.strip().lower()

        # 1. Check Household Alias Table (Highest Priority)
        if household_aliases:
            # Check by raw_text
            if cleaned_raw and cleaned_raw in household_aliases:
                target = household_aliases[cleaned_raw]
                cat_match = self._find_exact(target)
                if cat_match:
                    return MatchResult(
                        matched_name=cat_match.name,
                        confidence=1.0,
                        storage_zone=cat_match.storage_zone,
                        unit=cat_match.default_unit,
                        needs_review=False,
                        method="household_alias_raw",
                    )
                return MatchResult(
                    matched_name=target.title(),
                    confidence=1.0,
                    storage_zone=self._infer_zone(target),
                    unit="pcs",
                    needs_review=False,
                    method="household_alias_raw_custom",
                )
            # Check by name
            if cleaned_name and cleaned_name in household_aliases:
                target = household_aliases[cleaned_name]
                cat_match = self._find_exact(target)
                if cat_match:
                    return MatchResult(
                        matched_name=cat_match.name,
                        confidence=1.0,
                        storage_zone=cat_match.storage_zone,
                        unit=cat_match.default_unit,
                        needs_review=False,
                        method="household_alias_name",
                    )

        # 2. Check Exact Match or Alias Match in Catalog
        for ing in self._ingredients:
            if ing.name.lower() == cleaned_name:
                return MatchResult(
                    matched_name=ing.name,
                    confidence=1.0,
                    storage_zone=ing.storage_zone,
                    unit=ing.default_unit,
                    needs_review=False,
                    method="catalog_exact",
                )
            for alias in ing.aliases:
                if alias.lower() == cleaned_name or alias.lower() == cleaned_raw:
                    return MatchResult(
                        matched_name=ing.name,
                        confidence=0.98,
                        storage_zone=ing.storage_zone,
                        unit=ing.default_unit,
                        needs_review=False,
                        method="catalog_alias_exact",
                    )

        # 3. Check Substring / Word Match
        for ing in self._ingredients:
            if ing.name.lower() in cleaned_name or cleaned_name in ing.name.lower():
                return MatchResult(
                    matched_name=ing.name,
                    confidence=0.90,
                    storage_zone=ing.storage_zone,
                    unit=ing.default_unit,
                    needs_review=False,
                    method="catalog_substring",
                )
            for alias in ing.aliases:
                if alias.lower() in cleaned_name or (cleaned_raw and alias.lower() in cleaned_raw):
                    return MatchResult(
                        matched_name=ing.name,
                        confidence=0.88,
                        storage_zone=ing.storage_zone,
                        unit=ing.default_unit,
                        needs_review=False,
                        method="catalog_alias_substring",
                    )

        # 4. Semantic Embedding Similarity
        query_text = f"{cleaned_name} {cleaned_raw}".strip()
        query_vec = self.embedder.embed(query_text)
        best_ing: CatalogIngredient | None = None
        best_sim = -1.0

        for ing in self._ingredients:
            sim = self.embedder.similarity(query_vec, self._vectors[ing.name])
            if sim > best_sim:
                best_sim = sim
                best_ing = ing

        if best_ing and best_sim >= threshold:
            return MatchResult(
                matched_name=best_ing.name,
                confidence=round(best_sim, 2),
                storage_zone=best_ing.storage_zone,
                unit=best_ing.default_unit,
                needs_review=False,
                method="embedding_similarity",
            )

        # 5. Below threshold -> Needs Review
        fallback_name = name.strip().title() if name.strip() else (best_ing.name if best_ing else "Unknown Item")
        fallback_zone = best_ing.storage_zone if best_ing else self._infer_zone(fallback_name)
        fallback_unit = best_ing.default_unit if best_ing else "pcs"

        return MatchResult(
            matched_name=fallback_name,
            confidence=max(0.0, round(best_sim, 2)) if best_sim > 0 else 0.3,
            storage_zone=fallback_zone,
            unit=fallback_unit,
            needs_review=True,
            method="below_threshold",
        )

    def _find_exact(self, name: str) -> CatalogIngredient | None:
        target = name.strip().lower()
        return next((i for i in self._ingredients if i.name.lower() == target), None)
