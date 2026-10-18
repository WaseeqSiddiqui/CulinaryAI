from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from app.services.embedding_service import HashEmbeddingService


_WORD_RE = re.compile(r"[a-z0-9]+")
_SPELLING_NORMALIZATIONS = {
    "chilli": "chili",
    "chillies": "chilies",
    "vanaspati": "banaspati",
}
_FORM_WORDS = {
    "canned",
    "frozen",
    "ground",
    "masala",
    "powder",
    "seed",
    "seeds",
    "tin",
    "tinned",
}
_SPICE_BASE_WORDS = {
    "cardamom",
    "chili",
    "chilies",
    "cinnamon",
    "clove",
    "cloves",
    "coriander",
    "cumin",
    "haldi",
    "jeera",
    "pepper",
    "turmeric",
    "zeera",
}


def _normalize_text(value: str) -> str:
    """Return a token-normalized value suitable for safe phrase matching."""
    tokens = _WORD_RE.findall(value.lower())
    return " ".join(_SPELLING_NORMALIZATIONS.get(token, token) for token in tokens)


def _tokens(value: str) -> set[str]:
    return set(_normalize_text(value).split())


def _contains_phrase(text: str, phrase: str) -> bool:
    """Match complete words, never character fragments (for example dal in Dalda)."""
    normalized_text = _normalize_text(text)
    normalized_phrase = _normalize_text(phrase)
    if not normalized_text or not normalized_phrase:
        return False
    return re.search(
        rf"(?<![a-z0-9]){re.escape(normalized_phrase)}(?![a-z0-9])",
        normalized_text,
    ) is not None


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
    CatalogIngredient("Frozen Peas", "Frozen Food", "kg", "Freezer", ("frozen matar", "frozen green peas")),
    CatalogIngredient("Frozen Fries", "Frozen Food", "kg", "Freezer", ("french fries", "potato fries", "potatoes frozen")),
    CatalogIngredient("Frozen Chicken Nuggets", "Frozen Food", "pcs", "Freezer", ("chicken nuggets",)),
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
    CatalogIngredient("Watermelon", "Produce", "kg", "Pantry Shelf", ("water melon",)),
    CatalogIngredient("Coriander", "Produce", "pcs", "Fridge", ("cilantro", "dhaniya", "fresh coriander", "parsley")),
    CatalogIngredient("Mint", "Produce", "pcs", "Fridge", ("podina", "pudina", "fresh mint")),
    
    # Pantry Staples -> Pantry Shelf
    CatalogIngredient("Basmati Rice", "Grains", "kg", "Pantry Shelf", ("rice", "chawal", "super basmati", "brown rice", "jasmine rice")),
    CatalogIngredient("Wheat Flour", "Grains", "kg", "Pantry Shelf", ("flour", "atta", "chakki atta", "maida", "all purpose flour")),
    CatalogIngredient("Cooking Oil", "Oils", "L", "Pantry Shelf", ("vegetable oil", "canola oil", "sunflower oil", "tel")),
    CatalogIngredient("Olive Oil", "Oils", "ml", "Pantry Shelf", ("extra virgin olive oil", "pomace olive oil")),
    CatalogIngredient("Ghee", "Oils", "kg", "Pantry Shelf", ("desi ghee", "clarified butter", "banaspati ghee", "banaspati", "dalda", "dalda banaspati")),
    CatalogIngredient("Sugar", "Baking", "kg", "Pantry Shelf", ("white sugar", "cheeni", "cane sugar")),
    CatalogIngredient("Pasta", "Grains", "g", "Pantry Shelf", ("macaroni", "spaghetti", "penne", "fusilli")),
    CatalogIngredient("Noodles", "Grains", "pcs", "Pantry Shelf", ("instant noodles", "ramen", "maggi", "indomie", "knorr noodles")),
    CatalogIngredient("Lentils", "Pulses", "kg", "Pantry Shelf", ("daal", "dal", "moong daal", "masoor daal", "chana daal")),
    CatalogIngredient("Chickpeas", "Pulses", "kg", "Pantry Shelf", ("chana", "safaid chana", "garbanzo")),
    CatalogIngredient("Bread", "Bakery", "pcs", "Pantry Shelf", ("sandwich bread", "white bread", "brown bread", "loaf")),
    CatalogIngredient("Canned Tomatoes", "Canned Goods", "pcs", "Pantry Shelf", ("tomato puree", "tomato paste", "chopped tomatoes")),
    CatalogIngredient("Tomato Ketchup", "Condiments", "g", "Fridge", ("ketchup", "tomato sauce")),
    CatalogIngredient("Chili Garlic Sauce", "Condiments", "g", "Fridge", ("chilli garlic sauce",)),
    CatalogIngredient("Soy Sauce", "Condiments", "ml", "Pantry Shelf", ("dark soy sauce", "light soy sauce")),
    CatalogIngredient("Vinegar", "Condiments", "ml", "Pantry Shelf", ("white vinegar", "sirka", "apple cider vinegar")),
    CatalogIngredient("Tea", "Beverages", "g", "Pantry Shelf", ("chai", "black tea", "tapal", "lipton", "green tea")),
    CatalogIngredient("Coffee", "Beverages", "g", "Pantry Shelf", ("instant coffee", "nescafe", "ground coffee")),
    CatalogIngredient("Diet Cola", "Beverages", "pcs", "Fridge", ("cola", "coke", "pepsi", "soda", "diet coke")),
    CatalogIngredient("Mineral Water", "Beverages", "L", "Pantry Shelf", ("water", "drinking water", "nestle water")),

    # Spices -> Spice Rack
    CatalogIngredient("Salt", "Spices", "g", "Spice Rack", ("table salt", "iodized salt", "namak", "pink salt")),
    CatalogIngredient("Black Pepper", "Spices", "g", "Spice Rack", ("kali mirch", "black pepper powder", "peppercorns")),
    CatalogIngredient("Red Chili Powder", "Spices", "g", "Spice Rack", ("lal mirch", "chili powder", "red chili", "red chilli", "cayenne")),
    CatalogIngredient("Turmeric", "Spices", "g", "Spice Rack", ("haldi", "turmeric powder")),
    CatalogIngredient("Cumin", "Spices", "g", "Spice Rack", ("zeera", "jeera", "cumin seeds", "ground cumin")),
    CatalogIngredient("Coriander Powder", "Spices", "g", "Spice Rack", ("dhaniya powder", "ground coriander")),
    CatalogIngredient("Coriander Seeds", "Spices", "g", "Spice Rack", ("whole coriander seeds", "dhaniya seeds")),
    CatalogIngredient("Garam Masala", "Spices", "g", "Spice Rack", ("mixed spices", "all spice powder")),
    CatalogIngredient("Chicken Masala", "Spices", "g", "Spice Rack", ("chicken spice mix",)),
    CatalogIngredient("Fish Masala", "Spices", "g", "Spice Rack", ("fish spice mix",)),
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
        qualified_zone = self._qualified_zone(name)
        if qualified_zone:
            return qualified_zone

        if any(
            _contains_phrase(name, phrase)
            for phrase in ("ice cream", "fish", "prawn", "prawns", "shrimp")
        ):
            return "Freezer"
        if any(
            _contains_phrase(name, phrase)
            for phrase in (
                "milk",
                "egg",
                "eggs",
                "butter",
                "cheese",
                "yogurt",
                "chicken",
                "beef",
                "meat",
                "tomato",
                "salad",
                "spinach",
                "lemon",
            )
        ):
            return "Fridge"
        if _tokens(name) & (_SPICE_BASE_WORDS | {"salt", "spice", "spices"}):
            return "Spice Rack"
        return "Pantry Shelf"

    @staticmethod
    def _qualified_zone(text: str) -> str | None:
        """Honor product form before a base ingredient's usual storage zone."""
        normalized = _normalize_text(text)
        words = set(normalized.split())

        # This condiment remains refrigerated under the app's current policy.
        if _contains_phrase(normalized, "chili garlic sauce"):
            return "Fridge"
        if "frozen" in words:
            return "Freezer"
        if words & {"canned", "tin", "tinned"}:
            return "Pantry Shelf"
        if "masala" in words:
            return "Spice Rack"
        if _contains_phrase(normalized, "red chili"):
            return "Spice Rack"
        if words & {"ground", "powder", "seed", "seeds"} and words & _SPICE_BASE_WORDS:
            return "Spice Rack"
        if "powder" in words and words & {"baking", "cocoa", "milk", "protein"}:
            return "Pantry Shelf"
        return None

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
        cleaned_raw = _normalize_text(raw_text)
        cleaned_name = _normalize_text(name)

        # 1. Check Household Alias Table (Highest Priority)
        if household_aliases:
            normalized_aliases = {
                _normalize_text(source): target
                for source, target in household_aliases.items()
            }
            # Check by raw_text
            if cleaned_raw and cleaned_raw in normalized_aliases:
                target = normalized_aliases[cleaned_raw]
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
            if cleaned_name and cleaned_name in normalized_aliases:
                target = normalized_aliases[cleaned_name]
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

        # 2. Product form outranks a base ingredient. For example, frozen
        # chicken belongs in the freezer and chicken masala on the spice rack.
        qualified_text = f"{cleaned_name} {cleaned_raw}".strip()
        qualified_zone = self._qualified_zone(qualified_text)
        if qualified_zone:
            qualified_match = self._qualified_catalog_match(
                name=name,
                cleaned_name=cleaned_name,
                cleaned_raw=cleaned_raw,
                storage_zone=qualified_zone,
            )
            if qualified_match:
                return qualified_match

        # 3. Check Exact Match or Alias Match in Catalog
        for ing in self._ingredients:
            if _normalize_text(ing.name) == cleaned_name:
                return MatchResult(
                    matched_name=ing.name,
                    confidence=1.0,
                    storage_zone=ing.storage_zone,
                    unit=ing.default_unit,
                    needs_review=False,
                    method="catalog_exact",
                )
            for alias in ing.aliases:
                normalized_alias = _normalize_text(alias)
                if normalized_alias == cleaned_name or normalized_alias == cleaned_raw:
                    return MatchResult(
                        matched_name=ing.name,
                        confidence=0.98,
                        storage_zone=ing.storage_zone,
                        unit=ing.default_unit,
                        needs_review=False,
                        method="catalog_alias_exact",
                    )

        # 4. Boundary-aware phrase match. Rank all candidates so a specific
        # phrase such as "red chili" beats a generic alias such as "chili".
        phrase_match = self._best_phrase_match(cleaned_name, cleaned_raw)
        if phrase_match:
            ing, is_alias = phrase_match
            return MatchResult(
                matched_name=ing.name,
                confidence=0.88 if is_alias else 0.90,
                storage_zone=ing.storage_zone,
                unit=ing.default_unit,
                needs_review=False,
                method="catalog_alias_substring" if is_alias else "catalog_substring",
            )

        # 5. Hash-vector similarity is only meaningful when there is real
        # lexical overlap. Without this guard, unrelated one-word products can
        # collide in the hash vector and inherit an arbitrary catalog zone.
        query_text = f"{cleaned_name} {cleaned_raw}".strip()
        query_vec = self.embedder.embed(query_text)
        query_signal = self._significant_tokens(query_text)
        best_ing: CatalogIngredient | None = None
        best_sim = -1.0

        for ing in self._ingredients:
            ingredient_signal = self._significant_tokens(self._ingredient_text(ing))
            if not query_signal.intersection(ingredient_signal):
                continue
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

        # 6. Below threshold -> Needs Review. Never copy the nearest hash
        # candidate's zone or unit: it may only be a collision.
        fallback_source = name.strip() or raw_text.strip() or "Unknown Item"
        fallback_name = fallback_source.title()
        fallback_zone = self._infer_zone(f"{name} {raw_text}")

        return MatchResult(
            matched_name=fallback_name,
            confidence=max(0.0, round(best_sim, 2)) if best_sim > 0 else 0.3,
            storage_zone=fallback_zone,
            unit="pcs",
            needs_review=True,
            method="below_threshold",
        )

    def _qualified_catalog_match(
        self,
        *,
        name: str,
        cleaned_name: str,
        cleaned_raw: str,
        storage_zone: str,
    ) -> MatchResult | None:
        """Return a form-aware match only when the product has a known food signal."""
        query_signal = self._significant_tokens(f"{cleaned_name} {cleaned_raw}")
        if not query_signal:
            return None

        best_ing: CatalogIngredient | None = None
        best_overlap: tuple[int, int] = (0, 0)
        for ing in self._ingredients:
            ingredient_signal = self._significant_tokens(self._ingredient_text(ing))
            overlap = query_signal.intersection(ingredient_signal)
            score = (len(overlap), len("".join(overlap)))
            if score > best_overlap:
                best_overlap = score
                best_ing = ing

        if best_ing is None:
            return None

        exact_match = self._find_exact_or_alias(cleaned_name)
        if exact_match and exact_match.storage_zone == storage_zone:
            matched_name = exact_match.name
            unit = exact_match.default_unit
        elif best_ing.storage_zone == storage_zone:
            matched_name = best_ing.name
            unit = best_ing.default_unit
        else:
            matched_name = name.strip().title() or best_ing.name
            unit = "g" if storage_zone == "Spice Rack" else "pcs"

        return MatchResult(
            matched_name=matched_name,
            confidence=0.94,
            storage_zone=storage_zone,
            unit=unit,
            needs_review=False,
            method="storage_qualifier",
        )

    def _best_phrase_match(
        self,
        cleaned_name: str,
        cleaned_raw: str,
    ) -> tuple[CatalogIngredient, bool] | None:
        candidates: list[tuple[tuple[int, int, int, int], CatalogIngredient, bool]] = []
        for ing in self._ingredients:
            terms = ((ing.name, False), *((alias, True) for alias in ing.aliases))
            for term, is_alias in terms:
                normalized_term = _normalize_text(term)
                if not normalized_term:
                    continue
                in_name = bool(cleaned_name) and _contains_phrase(
                    cleaned_name, normalized_term
                )
                in_raw = bool(cleaned_raw) and _contains_phrase(
                    cleaned_raw, normalized_term
                )
                if not in_name and not in_raw:
                    continue
                score = (
                    len(normalized_term.split()),
                    len(normalized_term),
                    1 if in_name else 0,
                    0 if is_alias else 1,
                )
                candidates.append((score, ing, is_alias))

        if not candidates:
            return None
        _, ingredient, is_alias = max(candidates, key=lambda candidate: candidate[0])
        return ingredient, is_alias

    @staticmethod
    def _significant_tokens(value: str) -> set[str]:
        return _tokens(value) - _FORM_WORDS - {
            "brand",
            "fresh",
            "item",
            "national",
            "organic",
            "product",
        }

    def _find_exact(self, name: str) -> CatalogIngredient | None:
        target = _normalize_text(name)
        return next(
            (i for i in self._ingredients if _normalize_text(i.name) == target),
            None,
        )

    def _find_exact_or_alias(self, name: str) -> CatalogIngredient | None:
        target = _normalize_text(name)
        for ingredient in self._ingredients:
            if _normalize_text(ingredient.name) == target:
                return ingredient
            if any(_normalize_text(alias) == target for alias in ingredient.aliases):
                return ingredient
        return None
